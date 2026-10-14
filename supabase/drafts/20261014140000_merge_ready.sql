-- DRAFT, NOT APPLIED, not run by CI. Merge-ready schema: origin ids, aliases, staging, conflicts, import log.
-- Depends on the 20261014130000_data_status.sql draft.

create table if not exists public.import_runs (
  id bigint generated always as identity primary key,
  source_system text not null,
  file_or_url text, checksum text,
  started_at timestamptz not null default now(), finished_at timestamptz,
  rows_seen int default 0, inserted int default 0, updated int default 0,
  matched int default 0, conflicts int default 0, errors int default 0,
  run_by text, notes text
);

-- Origin on every content table; unique per source so re-imports upsert.
do $$
declare t text;
begin
  foreach t in array array[
    'firms','funds','fund_entities','people','legal_matters','filings','docket_entries','regulatory_records',
    'sanctions_checks','press_items','sources','evidence_cards','takeaways','score_results','fact_events',
    'site_updates','site_stats','ui_strings'
  ] loop
    execute format('alter table public.%I add column if not exists source_system text not null default %L', t, 'repo_json');
    execute format('alter table public.%I add column if not exists external_id text', t);
    execute format('alter table public.%I add column if not exists import_run_id bigint references public.import_runs(id) on delete set null', t);
    execute format('create unique index if not exists %I on public.%I (source_system, external_id) where external_id is not null', t || '_origin_uq', t);
  end loop;
end $$;

-- Stable identifiers + aliases for matching firms.
alter table public.firms add column if not exists sec_crd text, add column if not exists sec_file_no text,
  add column if not exists legal_name text, add column if not exists primary_domain text;
create unique index if not exists firms_sec_crd_uq on public.firms (sec_crd) where sec_crd is not null;
create table if not exists public.vc_aliases (
  id bigint generated always as identity primary key,
  firm_id uuid not null references public.firms(id) on delete cascade,
  alias_type text not null check (alias_type in ('name','short_name','legal_entity','domain','sec_crd','sec_file_no','former_name')),
  value text not null,
  source_system text not null default 'manual',
  created_at timestamptz not null default now()
);
create unique index if not exists vc_aliases_uq on public.vc_aliases (alias_type, lower(value));

-- Conflicting facts kept side by side.
create table if not exists public.vc_fact_conflicts (
  id bigint generated always as identity primary key,
  firm_id uuid not null references public.firms(id) on delete cascade,
  field text not null,
  fact_a_table text not null, fact_a_id text not null,
  fact_b_table text not null, fact_b_id text not null,
  status text not null default 'open' check (status in ('open','resolved')),
  resolution text, resolved_by text, resolved_at timestamptz,
  created_at timestamptz not null default now()
);

-- Staging schema: imports land here as test, then are promoted.
create schema if not exists staging;
create table if not exists staging.vc_profiles (like public.firms including defaults);
create table if not exists staging.sources (like public.sources including defaults);
create table if not exists staging.legal_matters (like public.legal_matters including defaults);
create table if not exists staging.press_items (like public.press_items including defaults);
alter table staging.vc_profiles add column if not exists match_status text default 'unmatched'
  check (match_status in ('unmatched','matched','ambiguous','new')),
  add column if not exists matched_firm_id uuid;
revoke all on schema staging from anon, authenticated;

-- RLS on new public tables (service role only for now).
alter table public.import_runs enable row level security;
alter table public.vc_aliases enable row level security;
alter table public.vc_fact_conflicts enable row level security;

-- Backfill origin for current rows (examples): firms external_id = slug.
-- update public.firms set source_system = 'repo_json', external_id = report_slug where external_id is null;
