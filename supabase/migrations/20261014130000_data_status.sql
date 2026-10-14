-- DRAFT, NOT APPLIED. Test vs real data flag, purge and promote workflow.
-- Lives in supabase/drafts/ so scripts/migrate.py and CI do not run it.
-- See toxybase/design/system/DATA-ARCHITECTURE.md §"Test vs real data".

do $$ begin
  create type public.data_status as enum ('test', 'real');
exception when duplicate_object then null; end $$;

-- 1. Flag on every content table. New rows default to 'test'; only the promote step makes them real.
do $$
declare t text;
begin
  foreach t in array array[
    'firms','funds','fund_entities','people','fund_people','investments','portfolio_companies','portfolio_metrics',
    'legal_matters','filings','docket_entries','regulatory_records','sanctions_checks','press_items','sources','fact_sources',
    'evidence_cards','evidence_lines','takeaways','ask_questions','copy_blocks','page_chips','list_items','firm_meta_items',
    'score_results','fact_events','site_updates','site_stats','ui_strings'
  ] loop
    execute format('alter table public.%I add column if not exists data_status public.data_status not null default %L', t, 'test');
    execute format('create index if not exists %I on public.%I (data_status)', t || '_data_status', t);
  end loop;
end $$;

-- 2. Backfill current content (reviewed Oct 14, 2026): everything published is real, except known unverified rows.
update public.firms set data_status = (case when is_test then 'test' else 'real' end)::public.data_status;
do $$
declare t text;
begin
  foreach t in array array[
    'funds','fund_entities','people','fund_people','investments','portfolio_companies','portfolio_metrics',
    'legal_matters','filings','docket_entries','regulatory_records','sanctions_checks','press_items','sources','fact_sources',
    'evidence_cards','evidence_lines','takeaways','ask_questions','copy_blocks','page_chips','list_items','firm_meta_items',
    'score_results','fact_events','site_updates'
  ] loop
    execute format('update public.%I set data_status = %L::public.data_status', t, 'real');
  end loop;
end $$;
update public.site_stats set data_status = (case when verified then 'real' else 'test' end)::public.data_status;
update public.ui_strings set data_status = (case when status = 'live' then 'real' else 'test' end)::public.data_status;
-- site_updates with unverified (Toxy) records: tag test.
update public.site_updates set data_status = 'test' where verification = 'toxy';

-- 3. Source requirement for real facts.
alter table public.sources add column if not exists retrieved_at timestamptz;
alter table public.press_items add column if not exists retrieved_at timestamptz;
alter table public.sources add constraint sources_real_needs_source
  check (data_status <> 'real' or (url is not null and url <> '' and retrieved_at is not null)) not valid;
alter table public.press_items add constraint press_real_needs_source
  check (data_status <> 'real' or (url is not null and url <> '' and retrieved_at is not null)) not valid;
-- Backfill (Alex default): retrieved_at = report import date, flagged for a later re-fetch by the workers.
alter table public.sources add column if not exists needs_refetch boolean not null default false;
alter table public.press_items add column if not exists needs_refetch boolean not null default false;
update public.sources set retrieved_at = created_at, needs_refetch = true where retrieved_at is null;
update public.press_items set retrieved_at = created_at, needs_refetch = true where retrieved_at is null;
alter table public.sources validate constraint sources_real_needs_source;
alter table public.press_items validate constraint press_real_needs_source;
-- New-flow ui_strings (status = 'planned') stay 'test' until the flow ships (set in step 2).

-- 4. Promote workflow: the only way to mark a fact real.
create or replace function public.promote_source(p_id uuid, p_retrieved_at timestamptz default now())
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.sources
     set retrieved_at = coalesce(retrieved_at, p_retrieved_at), data_status = 'real'
   where id = p_id and url is not null and url <> '';
  if not found then raise exception 'source % needs a URL before it can be real', p_id; end if;
end $$;
revoke all on function public.promote_source(uuid, timestamptz) from public, anon, authenticated;

-- AI text only from real facts (applies to the planned vc_ai_summaries/vc_ai_summary_facts tables):
--   trigger on vc_ai_summaries before update when new.review_status = 'approved':
--     raise if exists (select 1 from vc_ai_summary_facts l join vc_source_facts f on f.id = l.fact_id
--                       where l.summary_id = new.id and (f.data_status <> 'real' or f.status <> 'current'))
--     raise if not exists (select 1 from vc_ai_summary_facts where summary_id = new.id)

-- 5. One-command purge of test data. Cascade-safe: firms cascade to all VC-owned rows;
--    user rows referencing a purged firm follow their FK rule (watchlist -> set null + "Removed" once migrated).
create or replace function public.purge_test_data(p_dry_run boolean default true)
returns table (table_name text, rows_affected bigint)
language plpgsql security definer set search_path = public as $$
declare t text; n bigint;
begin
  -- children first is unnecessary for cascaded tables, but standalone test rows need their own delete
  foreach t in array array[
    'evidence_lines','evidence_cards','takeaways','ask_questions','copy_blocks','page_chips','list_items','firm_meta_items',
    'docket_entries','filings','legal_matters','regulatory_records','sanctions_checks','fact_sources','sources','press_items',
    'score_results','fact_events','site_updates','site_stats','ui_strings',
    'investments','fund_people','fund_entities','portfolio_metrics','portfolio_companies','people','funds','firms'
  ] loop
    if p_dry_run then
      execute format('select count(*) from public.%I where data_status = %L::public.data_status', t, 'test') into n;
    else
      execute format('delete from public.%I where data_status = %L::public.data_status', t, 'test');
      get diagnostics n = row_count;
    end if;
    table_name := t; rows_affected := n; return next;
  end loop;
end $$;
revoke all on function public.purge_test_data(boolean) from public, anon, authenticated;
-- Usage:  select * from public.purge_test_data();        -- dry run, counts only
--         select * from public.purge_test_data(false);   -- delete all test rows

-- 6. Public reads show real only (example for the landing list; apply the same filter in RPCs/build bundle):
--   create or replace view public.firms_live as select * from public.firms
--     where data_status = 'real' and published and not is_test;
