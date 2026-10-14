-- DRAFT, NOT APPLIED, not run by CI. VC profile layers (benchmark: a16z). See design/system/VC-PROFILE.md.
-- Depends on drafts 20261014130000_data_status.sql and 20261014140000_merge_ready.sql.
-- vc_profiles is the existing public.firms table (renamed via view to avoid breaking code now).

create or replace view public.vc_profiles with (security_invoker = true) as select * from public.firms;

alter table public.firms add column if not exists founded_year int,
  add column if not exists disambiguation text,
  add column if not exists report_date date,
  add column if not exists deleted_at timestamptz;

create table if not exists public.vc_source_facts (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  fact_type text not null check (fact_type in ('sec_crd','legal_entity','fund_fact','regulatory_record','legal_matter',
    'sanctions_check','press_item','board_seat','partner_move','media_reach','portfolio_size','portfolio_event_count',
    'portfolio_health','portfolio_litigation_rate','founder_experience')),
  section text not null,
  value jsonb not null,
  source_url text, source_label text, source_type text,
  retrieved_at timestamptz, record_id text, quote text,
  status text not null default 'current' check (status in ('current','superseded')),
  superseded_by uuid references public.vc_source_facts(id),
  counted boolean, points numeric,
  data_status public.data_status not null default 'test',
  needs_refetch boolean not null default false,
  source_system text not null default 'manual', external_id text,
  import_run_id bigint references public.import_runs(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint fact_real_needs_source check (data_status <> 'real' or (source_url is not null and retrieved_at is not null))
);
create unique index if not exists vc_source_facts_origin_uq on public.vc_source_facts (source_system, external_id) where external_id is not null;
create index if not exists vc_source_facts_firm on public.vc_source_facts (firm_id, fact_type) where status = 'current';

create table if not exists public.vc_ai_summaries (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  kind text not null check (kind in ('verdict','verdict_sub','summary','takeaway','score_part_rule','score_input_why',
    'not_counted_why','press_why','ask_question','section_note')),
  variant text, section text not null, sort_order int default 0,
  text jsonb not null,
  model text, prompt_version text, generated_at timestamptz not null default now(),
  review_status text not null default 'draft' check (review_status in ('draft','approved','rejected')),
  stale boolean not null default false,
  data_status public.data_status not null default 'test',
  created_at timestamptz not null default now()
);
create table if not exists public.vc_ai_summary_facts (
  summary_id uuid not null references public.vc_ai_summaries(id) on delete cascade,
  fact_id uuid not null references public.vc_source_facts(id) on delete cascade,
  primary key (summary_id, fact_id)
);

-- Approve only when citing >=1 fact and all cited facts are real + current.
create or replace function public.vc_ai_check_approve() returns trigger language plpgsql as $$
begin
  if new.review_status = 'approved' then
    if not exists (select 1 from public.vc_ai_summary_facts where summary_id = new.id) then
      raise exception 'AI summary % cites no facts', new.id; end if;
    if exists (select 1 from public.vc_ai_summary_facts l join public.vc_source_facts f on f.id = l.fact_id
               where l.summary_id = new.id and (f.data_status <> 'real' or f.status <> 'current')) then
      raise exception 'AI summary % cites test or superseded facts', new.id; end if;
  end if;
  return new;
end $$;
drop trigger if exists vc_ai_check_approve on public.vc_ai_summaries;
create trigger vc_ai_check_approve before insert or update on public.vc_ai_summaries
  for each row execute function public.vc_ai_check_approve();

-- Fact change -> linked summaries stale.
create or replace function public.vc_fact_mark_stale() returns trigger language plpgsql as $$
begin
  update public.vc_ai_summaries s set stale = true
   where exists (select 1 from public.vc_ai_summary_facts l where l.summary_id = s.id and l.fact_id = new.id);
  return new;
end $$;
drop trigger if exists vc_fact_mark_stale on public.vc_source_facts;
create trigger vc_fact_mark_stale after update of value, status, source_url on public.vc_source_facts
  for each row execute function public.vc_fact_mark_stale();

-- Scores (derived).
create table if not exists public.vc_scores (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  method_version text not null, score_exact numeric not null, score_shown int not null,
  band text not null, range_low numeric, range_high numeric, coverage_pct numeric,
  rank_place int, rank_of int, computed_at timestamptz not null default now(),
  is_current boolean not null default true,
  data_status public.data_status not null default 'test'
);
create table if not exists public.vc_score_parts (
  id uuid primary key default gen_random_uuid(),
  score_id uuid not null references public.vc_scores(id) on delete cascade,
  part_key text not null, name text not null, got numeric not null, max_label text, sort_order int
);
create table if not exists public.vc_score_inputs (
  id uuid primary key default gen_random_uuid(),
  part_id uuid not null references public.vc_score_parts(id) on delete cascade,
  name text not null, points text not null, fact_id uuid references public.vc_source_facts(id) on delete set null
);

-- Completeness vs the a16z benchmark (required items only; see VC-PROFILE.md).
create or replace view public.vc_profile_completeness with (security_invoker = true) as
select f.id as firm_id, f.slug,
  (f.sec_crd is not null or f.legal_name is not null)::int
  + exists(select 1 from public.vc_aliases a where a.firm_id = f.id)::int
  + exists(select 1 from public.vc_source_facts x where x.firm_id = f.id and x.fact_type = 'fund_fact')::int
  + exists(select 1 from public.vc_source_facts x where x.firm_id = f.id and x.fact_type = 'sanctions_check')::int
  + exists(select 1 from public.vc_source_facts x where x.firm_id = f.id and x.fact_type = 'legal_matter')::int
  + exists(select 1 from public.vc_scores s where s.firm_id = f.id and s.is_current)::int
  + exists(select 1 from public.vc_ai_summaries s where s.firm_id = f.id and s.kind = 'verdict' and s.review_status = 'approved')::int
  + ((select count(*) from public.vc_ai_summaries s where s.firm_id = f.id and s.kind = 'takeaway') >= 3)::int
  + (not exists(select 1 from public.vc_source_facts x where x.firm_id = f.id and x.status = 'current' and x.data_status <> 'real'))::int
  + (not exists(select 1 from public.vc_ai_summaries s where s.firm_id = f.id and s.stale))::int
  as required_present, 10 as required_total
from public.firms f;

alter table public.vc_source_facts enable row level security;
alter table public.vc_ai_summaries enable row level security;
alter table public.vc_ai_summary_facts enable row level security;
alter table public.vc_scores enable row level security;
alter table public.vc_score_parts enable row level security;
alter table public.vc_score_inputs enable row level security;

-- Purge now also covers the VC fact / AI layers (links cascade from facts and summaries).
create or replace function public.purge_test_data(p_dry_run boolean default true)
returns table (table_name text, rows_affected bigint)
language plpgsql security definer set search_path = public as $$
declare t text; n bigint;
begin
  foreach t in array array[
    'vc_ai_summaries','vc_source_facts','vc_scores',
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
