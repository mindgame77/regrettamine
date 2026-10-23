-- Firm LP (limited partner) data (staging research tables; approved by Alex 2026-10-23).
-- firm_lps: one row per LP commitment / relationship of a research firm (research_queue.registry_id).
-- firm_lp_summary: per-firm count; at more than 100 LPs the firm is marked lp_count_band='100+' (capped) and we stop listing.
-- Writes: research-ingest submit (optional body.lps array) via research_store_lps(); backfill below from accepted submissions.
-- Backup: public.*_bak_pre_lp + /workspace/toxybase/backups/2026-10-23-pre-lp-table; git tag pre-lp-table.
-- Rollback: drop function research_store_lps(text,bigint,jsonb,boolean); drop trigger firm_lps_summary_sync on firm_lps;
--   drop function firm_lps_summary_refresh(); drop table firm_lp_summary; drop table firm_lps.
create table if not exists public.firm_lps (
  id bigserial primary key,
  registry_id text not null references public.research_queue(registry_id) on delete cascade,
  lp_name text not null check (length(trim(lp_name)) between 2 and 300),
  lp_type text not null default 'other' check (lp_type in ('pension','endowment','foundation','sovereign','family_office','fund_of_funds','insurance','corporate','other')),
  country text,
  commitment_amount numeric check (commitment_amount is null or commitment_amount >= 0),
  currency text check (currency is null or currency ~ '^[A-Z]{3}$'),
  fund_name text,
  commitment_year int check (commitment_year is null or commitment_year between 1950 and 2100),
  status text not null default 'lead' check (status in ('confirmed','lead')),
  source_url text not null check (source_url ~* '^https?://'),
  source_title text,
  checked_at timestamptz not null default now(),
  sanctions_result text not null default 'not_screened' check (sanctions_result in ('clear','possible_match','match','not_screened')),
  notes text,
  submission_id bigint references public.research_submissions(id) on delete set null,
  bot_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now());
create unique index if not exists firm_lps_uniq on public.firm_lps (registry_id, lower(lp_name), coalesce(lower(fund_name),''));
create index if not exists firm_lps_firm on public.firm_lps (registry_id, status);

create table if not exists public.firm_lp_summary (
  registry_id text primary key references public.research_queue(registry_id) on delete cascade,
  lp_count int not null default 0,          -- distinct LP names listed
  confirmed_count int not null default 0,
  lead_count int not null default 0,
  over_100 boolean not null default false,  -- true => firm has more than 100 LPs; stop listing
  lp_count_band text not null default '0' check (lp_count_band in ('0','1-9','10-49','50-100','100+')),
  updated_at timestamptz not null default now());

do $$ declare t text; begin
  foreach t in array array['firm_lps','firm_lp_summary'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated, public', t);
  end loop; end $$;
-- no policies => anon/authenticated get nothing; service_role bypasses RLS (same as other research tables)

create or replace function public.firm_lps_summary_refresh() returns trigger
language plpgsql security definer set search_path = public as $$
declare rid text := coalesce(new.registry_id, old.registry_id); n int; c int; l int; o boolean;
begin
  select count(distinct lower(lp_name)), count(distinct lower(lp_name)) filter (where status='confirmed'),
         count(distinct lower(lp_name)) filter (where status='lead') into n, c, l from firm_lps where registry_id = rid;
  select coalesce(over_100,false) into o from firm_lp_summary where registry_id = rid;
  o := coalesce(o,false) or n > 100;
  insert into firm_lp_summary (registry_id, lp_count, confirmed_count, lead_count, over_100, lp_count_band, updated_at)
  values (rid, n, c, l, o, case when o then '100+' when n = 0 then '0' when n < 10 then '1-9' when n < 50 then '10-49' else '50-100' end, now())
  on conflict (registry_id) do update set lp_count=excluded.lp_count, confirmed_count=excluded.confirmed_count,
    lead_count=excluded.lead_count, over_100=excluded.over_100, lp_count_band=excluded.lp_count_band, updated_at=now();
  return null;
end $$;
drop trigger if exists firm_lps_summary_sync on public.firm_lps;
create trigger firm_lps_summary_sync after insert or update or delete on public.firm_lps
  for each row execute function public.firm_lps_summary_refresh();

-- store validated LPs of one ACCEPTED submission. Upsert on (firm, lp_name, fund_name). Stops at 100 distinct LPs per firm:
-- extra LPs are not listed, firm is marked over_100 / '100+'. p_over_100 = bot says the firm has more than 100 LPs.
create or replace function public.research_store_lps(p_id text, p_submission bigint, p_lps jsonb, p_over_100 boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e jsonb; stored int := 0; skipped int := 0; n int;
begin
  if not exists (select 1 from research_submissions where id = p_submission and registry_id = p_id and valid) then
    return jsonb_build_object('ok',false,'error','submission not found / not valid'); end if;
  for e in select * from jsonb_array_elements(coalesce(p_lps,'[]'::jsonb)) loop
    select count(distinct lower(lp_name)) into n from firm_lps where registry_id = p_id;
    if n >= 100 and not exists (select 1 from firm_lps where registry_id=p_id and lower(lp_name)=lower(e->>'lp_name')) then
      skipped := skipped + 1; continue; end if;
    insert into firm_lps (registry_id, lp_name, lp_type, country, commitment_amount, currency, fund_name, commitment_year, status,
      source_url, source_title, checked_at, sanctions_result, notes, submission_id, bot_id)
    select p_id, trim(e->>'lp_name'), coalesce(e->>'lp_type','other'), e->>'country', (e->>'commitment_amount')::numeric, upper(e->>'currency'),
      nullif(trim(e->>'fund_name'),''), (e->>'commitment_year')::int, coalesce(e->>'status','lead'), e->>'source_url', e->>'source_title',
      coalesce((e->>'checked_at')::timestamptz, now()), coalesce(e->>'sanctions_result','not_screened'), e->>'notes', p_submission, s.bot_id
      from research_submissions s where s.id = p_submission
    on conflict (registry_id, lower(lp_name), coalesce(lower(fund_name),'')) do update set lp_type=excluded.lp_type, country=excluded.country,
      commitment_amount=excluded.commitment_amount, currency=excluded.currency, commitment_year=excluded.commitment_year, status=excluded.status,
      source_url=excluded.source_url, source_title=excluded.source_title, checked_at=excluded.checked_at,
      sanctions_result=excluded.sanctions_result, notes=excluded.notes, submission_id=excluded.submission_id, bot_id=excluded.bot_id, updated_at=now();
    stored := stored + 1;
  end loop;
  if coalesce(p_over_100,false) or skipped > 0 then
    insert into firm_lp_summary (registry_id, over_100, lp_count_band) values (p_id, true, '100+')
      on conflict (registry_id) do update set over_100=true, lp_count_band='100+', updated_at=now();
  end if;
  return jsonb_build_object('ok',true,'stored',stored,'not_listed_over_100',skipped,
    'lp_count_band',(select lp_count_band from firm_lp_summary where registry_id=p_id));
end $$;
revoke all on function public.research_store_lps(text,bigint,jsonb,boolean) from public, anon, authenticated;
grant execute on function public.research_store_lps(text,bigint,jsonb,boolean) to service_role;
revoke all on function public.firm_lps_summary_refresh() from public, anon, authenticated;
