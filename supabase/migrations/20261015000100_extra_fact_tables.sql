-- Fields the Oct 14 research import could not place. All VC-owned (firm_id -> firms on delete cascade),
-- with provenance (source_system, external_id). Only raw facts: no workbook scores, confidence, trust tiers
-- or AI conclusions are stored. A row is real only with source_url + retrieved_at (constraint below).

-- Registry identifiers of the firm's legal entities and their status.
create table if not exists public.vc_entity_identifiers (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  entity text,                     -- 'firm', 'partner:<name>', or a legal entity name as written in the source
  field text not null,             -- original workbook field name
  value text not null,             -- raw value as published by the source
  source_url text, source_label text, quote text, published_date date, retrieved_at timestamptz,
  data_status public.data_status not null default 'test',
  source_system text not null, external_id text not null,
  import_run_id bigint references public.import_runs(id) on delete set null,
  created_at timestamptz not null default now(),
  id_type text not null check (id_type in ('cik','lei','company_number','entity_status')),
  id_value text,                   -- parsed identifier (CIK digits, LEI, registry number); null for entity_status
  jurisdiction text,
  constraint vc_entity_identifiers_real_needs_source check (data_status <> 'real' or (source_url is not null and source_url <> '' and retrieved_at is not null))
);
create unique index if not exists vc_entity_identifiers_origin_uq on public.vc_entity_identifiers (source_system, external_id);
create index if not exists vc_entity_identifiers_firm on public.vc_entity_identifiers (firm_id, data_status);
alter table public.vc_entity_identifiers enable row level security;
revoke all on public.vc_entity_identifiers from anon, authenticated;
drop policy if exists vc_entity_identifiers_admin_all on public.vc_entity_identifiers;
create policy vc_entity_identifiers_admin_all on public.vc_entity_identifiers for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Partner history: careers, prior firms, companies founded, deals led, team, statements.
create table if not exists public.vc_partner_history (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  entity text,                     -- 'firm', 'partner:<name>', or a legal entity name as written in the source
  field text not null,             -- original workbook field name
  value text not null,             -- raw value as published by the source
  source_url text, source_label text, quote text, published_date date, retrieved_at timestamptz,
  data_status public.data_status not null default 'test',
  source_system text not null, external_id text not null,
  import_run_id bigint references public.import_runs(id) on delete set null,
  created_at timestamptz not null default now(),
  person_name text,
  person_id uuid references public.people(id) on delete set null,
  kind text not null check (kind in ('career_stint','prior_firm','founded_company','deal_led','team','partner_statement')),
  organization text,
  constraint vc_partner_history_real_needs_source check (data_status <> 'real' or (source_url is not null and source_url <> '' and retrieved_at is not null))
);
create unique index if not exists vc_partner_history_origin_uq on public.vc_partner_history (source_system, external_id);
create index if not exists vc_partner_history_firm on public.vc_partner_history (firm_id, data_status);
alter table public.vc_partner_history enable row level security;
revoke all on public.vc_partner_history from anon, authenticated;
drop policy if exists vc_partner_history_admin_all on public.vc_partner_history;
create policy vc_partner_history_admin_all on public.vc_partner_history for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Political donations (FEC) and lobbying disclosures (LDA).
create table if not exists public.vc_political_activity (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  entity text,                     -- 'firm', 'partner:<name>', or a legal entity name as written in the source
  field text not null,             -- original workbook field name
  value text not null,             -- raw value as published by the source
  source_url text, source_label text, quote text, published_date date, retrieved_at timestamptz,
  data_status public.data_status not null default 'test',
  source_system text not null, external_id text not null,
  import_run_id bigint references public.import_runs(id) on delete set null,
  created_at timestamptz not null default now(),
  person_name text,                -- null for firm-level lobbying
  kind text not null check (kind in ('political_donation','lobbying_spend','lobbying_issue')),
  constraint vc_political_activity_real_needs_source check (data_status <> 'real' or (source_url is not null and source_url <> '' and retrieved_at is not null))
);
create unique index if not exists vc_political_activity_origin_uq on public.vc_political_activity (source_system, external_id);
create index if not exists vc_political_activity_firm on public.vc_political_activity (firm_id, data_status);
alter table public.vc_political_activity enable row level security;
revoke all on public.vc_political_activity from anon, authenticated;
drop policy if exists vc_political_activity_admin_all on public.vc_political_activity;
create policy vc_political_activity_admin_all on public.vc_political_activity for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- What the firm says about itself (focus, geography, team size). Loaded as needs_proof; real only after an independent source.
create table if not exists public.vc_firm_claims (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  entity text,                     -- 'firm', 'partner:<name>', or a legal entity name as written in the source
  field text not null,             -- original workbook field name
  value text not null,             -- raw value as published by the source
  source_url text, source_label text, quote text, published_date date, retrieved_at timestamptz,
  data_status public.data_status not null default 'test',
  source_system text not null, external_id text not null,
  import_run_id bigint references public.import_runs(id) on delete set null,
  created_at timestamptz not null default now(),
  subject text,
  kind text not null check (kind in ('stated_focus_sector','stated_focus_stage','stated_geography','team_size','investing_partner_count','platform_team')),
  constraint vc_firm_claims_real_needs_source check (data_status <> 'real' or (source_url is not null and source_url <> '' and retrieved_at is not null))
);
create unique index if not exists vc_firm_claims_origin_uq on public.vc_firm_claims (source_system, external_id);
create index if not exists vc_firm_claims_firm on public.vc_firm_claims (firm_id, data_status);
alter table public.vc_firm_claims enable row level security;
revoke all on public.vc_firm_claims from anon, authenticated;
drop policy if exists vc_firm_claims_admin_all on public.vc_firm_claims;
create policy vc_firm_claims_admin_all on public.vc_firm_claims for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Raw context notes, community/forum founder reports, and negative aliases (names that are NOT this firm).
create table if not exists public.vc_context_notes (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  entity text,                     -- 'firm', 'partner:<name>', or a legal entity name as written in the source
  field text not null,             -- original workbook field name
  value text not null,             -- raw value as published by the source
  source_url text, source_label text, quote text, published_date date, retrieved_at timestamptz,
  data_status public.data_status not null default 'test',
  source_system text not null, external_id text not null,
  import_run_id bigint references public.import_runs(id) on delete set null,
  created_at timestamptz not null default now(),
  kind text not null check (kind in ('context','community_report','negative_alias')),
  constraint vc_context_notes_real_needs_source check (data_status <> 'real' or (source_url is not null and source_url <> '' and retrieved_at is not null))
);
create unique index if not exists vc_context_notes_origin_uq on public.vc_context_notes (source_system, external_id);
create index if not exists vc_context_notes_firm on public.vc_context_notes (firm_id, data_status);
alter table public.vc_context_notes enable row level security;
revoke all on public.vc_context_notes from anon, authenticated;
drop policy if exists vc_context_notes_admin_all on public.vc_context_notes;
create policy vc_context_notes_admin_all on public.vc_context_notes for all to authenticated using (public.is_admin()) with check (public.is_admin());


-- Promote: test or needs_proof -> real, only when a source URL and retrieved_at exist (or are given now).
drop function if exists public.promote_source(uuid, timestamptz);
create or replace function public.promote_source(p_id uuid, p_retrieved_at timestamptz default now(), p_source_url text default null)
returns text language plpgsql security definer set search_path = public as $$
declare t text; n int;
begin
  update public.sources
     set url = coalesce(nullif(url, ''), p_source_url), retrieved_at = coalesce(retrieved_at, p_retrieved_at), data_status = 'real'
   where id = p_id and coalesce(nullif(url, ''), p_source_url) is not null;
  get diagnostics n = row_count; if n > 0 then return 'sources'; end if;
  foreach t in array array['vc_source_facts','vc_entity_identifiers','vc_partner_history','vc_political_activity','vc_firm_claims','vc_context_notes'] loop
    execute format('update public.%I set source_url = coalesce(nullif(source_url, %L), $2), retrieved_at = coalesce(retrieved_at, $3), data_status = %L
                     where id = $1 and data_status in (%L, %L) and coalesce(nullif(source_url, %L), $2) is not null', t, '', 'real', 'test', 'needs_proof', '')
      using p_id, p_source_url, p_retrieved_at;
    get diagnostics n = row_count; if n > 0 then return t; end if;
  end loop;
  raise exception 'row % not found, already real, or has no source URL', p_id;
end $$;
revoke all on function public.promote_source(uuid, timestamptz, text) from public, anon, authenticated;

-- Purge: deletes data_status = 'test' ONLY. needs_proof and real rows are never touched.
create or replace function public.purge_test_data(p_dry_run boolean default true)
returns table (table_name text, rows_affected bigint)
language plpgsql security definer set search_path = public as $$
declare t text; n bigint;
begin
  foreach t in array array[
    'vc_entity_identifiers','vc_partner_history','vc_political_activity','vc_firm_claims','vc_context_notes',
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

-- fact_record_count() is unchanged: it counts seed rows plus import rows that are 'real'. The new tables have no
-- fact_events trigger, and needs_proof/test rows never count.
