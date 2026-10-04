-- Regrettamine schema. Matches docs/data-model.md.
-- Safe on a fresh Postgres and on Supabase (auth schema already exists there).

create extension if not exists pgcrypto;

-- On Supabase, auth.users already exists and the postgres role cannot touch the auth schema.
do $$
begin
  if to_regclass('auth.users') is null then
    execute 'create schema if not exists auth';
    execute 'create table auth.users (id uuid primary key default gen_random_uuid(), email text)';
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'auth' and p.proname = 'uid'
  ) then
    execute $fn$
      create function auth.uid() returns uuid
      language sql stable
      as $body$
        select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
      $body$
    $fn$;
  end if;
end $$;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- Firms, vehicles, people
-- ---------------------------------------------------------------------------

create table public.firms (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  initials text,
  short_name text,
  hq text,
  metro text,
  founded_year integer,
  firm_type text,
  aum_billions numeric,
  aum_display text,
  aum_as_of text,
  aum_stale boolean not null default false,
  aum_source text,
  list_score integer,
  list_band text,
  list_v2 boolean not null default false,
  list_range_low integer,
  list_range_high integer,
  list_previous_score integer,
  list_coverage integer,
  list_verdict text,
  list_legal_active integer not null default 0,
  legal_note text,
  updated_on date,
  updated_ts text,
  updated_label text,
  report_slug text,
  list_sort integer not null default 0,
  published boolean not null default false,
  is_test boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint firms_test_not_published check (not (is_test and published))
);

create table public.funds (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  name text not null,
  vintage integer,
  size_usd numeric,
  status text,
  vehicle_kind text,
  notes text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.fund_entities (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  fund_id uuid references public.funds(id) on delete cascade,
  name text not null,
  entity_kind text,
  crd text,
  jurisdiction text,
  notes text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.people (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.fund_people (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.people(id) on delete cascade,
  firm_id uuid not null references public.firms(id) on delete cascade,
  fund_id uuid references public.funds(id) on delete set null,
  role text not null,
  start_date date,
  end_date date,
  date_precision text,
  notes text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Portfolio and reviews
-- ---------------------------------------------------------------------------

create table public.portfolio_companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  domain text,
  sector text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.company_founders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.portfolio_companies(id) on delete cascade,
  person_id uuid not null references public.people(id) on delete cascade,
  title text,
  start_date date,
  end_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.investments (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  fund_id uuid references public.funds(id) on delete set null,
  company_id uuid not null references public.portfolio_companies(id) on delete cascade,
  round_name text,
  invested_on date,
  is_lead boolean,
  board_seat boolean not null default false,
  board_person_id uuid references public.people(id) on delete set null,
  outcome text,
  outcome_on date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  fund_id uuid references public.funds(id) on delete set null,
  company_id uuid references public.portfolio_companies(id) on delete set null,
  founder_person_id uuid references public.people(id) on delete set null,
  partner_person_id uuid references public.people(id) on delete set null,
  body text,
  first_hand boolean not null default false,
  verification_status text not null default 'unverified',
  moderation_status text not null default 'pending',
  reviewed_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.review_ratings (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references public.reviews(id) on delete cascade,
  dimension text not null,
  score numeric not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (review_id, dimension)
);

-- ---------------------------------------------------------------------------
-- Legal, regulatory, sanctions, press
-- ---------------------------------------------------------------------------

create table public.legal_matters (
  id uuid primary key default gen_random_uuid(),
  source_key text,
  title text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.legal_matter_firms (
  id uuid primary key default gen_random_uuid(),
  matter_id uuid not null references public.legal_matters(id) on delete cascade,
  firm_id uuid not null references public.firms(id) on delete cascade,
  fund_id uuid references public.funds(id) on delete set null,
  party_role text,
  status text,
  counted boolean not null default false,
  relevance text,
  points numeric,
  year_label text,
  summary text,
  detail text,
  badge text,
  tone text,
  sort_order integer not null default 0,
  featured_rank integer,
  evidence_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.legal_matter_parties (
  id uuid primary key default gen_random_uuid(),
  matter_id uuid not null references public.legal_matters(id) on delete cascade,
  name text not null,
  party_role text,
  person_id uuid references public.people(id) on delete set null,
  firm_id uuid references public.firms(id) on delete set null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.filings (
  id uuid primary key default gen_random_uuid(),
  matter_id uuid not null references public.legal_matters(id) on delete cascade,
  filed_on date,
  court text,
  docket_number text,
  title text,
  url text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.docket_entries (
  id uuid primary key default gen_random_uuid(),
  matter_id uuid not null references public.legal_matters(id) on delete cascade,
  filing_id uuid references public.filings(id) on delete set null,
  entered_on date,
  entry_no text,
  description text,
  url text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.legal_groups (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  parent_id uuid references public.legal_groups(id) on delete cascade,
  title text,
  note text,
  summary text,
  hint text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.legal_group_items (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.legal_groups(id) on delete cascade,
  evidence_key text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.regulatory_records (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  fund_id uuid references public.funds(id) on delete set null,
  title text not null,
  detail text,
  points numeric,
  icon text,
  tone text,
  points_label text,
  evidence_key text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.sanctions_checks (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  fund_id uuid references public.funds(id) on delete set null,
  person_id uuid references public.people(id) on delete set null,
  entity_id uuid references public.fund_entities(id) on delete set null,
  checked_on date,
  result text,
  exact_identity_match boolean,
  points numeric,
  title text,
  detail text,
  note text,
  is_clear boolean,
  evidence_key text,
  link_label text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.press_items (
  id uuid primary key default gen_random_uuid(),
  publisher text,
  domain text,
  url text,
  published_on date,
  published_label text,
  headline text,
  sentiment text,
  why text,
  group_label text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint press_items_sentiment check (sentiment is null or sentiment in ('pos', 'neu', 'neg'))
);

create table public.press_item_firms (
  press_item_id uuid not null references public.press_items(id) on delete cascade,
  firm_id uuid not null references public.firms(id) on delete cascade,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (press_item_id, firm_id)
);

-- ---------------------------------------------------------------------------
-- Sources
-- ---------------------------------------------------------------------------

create table public.sources (
  id uuid primary key default gen_random_uuid(),
  url text not null unique,
  publisher text,
  title text,
  domain text,
  verified boolean not null default false,
  junk boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.fact_sources (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.sources(id) on delete cascade,
  firm_id uuid references public.firms(id) on delete cascade,
  fact_type text not null,
  fact_id uuid not null,
  label text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Narrative
-- ---------------------------------------------------------------------------

create table public.takeaways (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  fund_id uuid references public.funds(id) on delete cascade,
  sort_order integer not null default 0,
  title text not null,
  body text,
  evidence_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.ask_questions (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  fund_id uuid references public.funds(id) on delete cascade,
  sort_order integer not null default 0,
  number_label text,
  title text,
  question text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.copy_blocks (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  fund_id uuid references public.funds(id) on delete cascade,
  block_key text not null,
  body text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index copy_blocks_firm_key
  on public.copy_blocks (firm_id, block_key)
  where fund_id is null;

create unique index copy_blocks_fund_key
  on public.copy_blocks (fund_id, block_key)
  where fund_id is not null;

create table public.page_chips (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  slot text not null,
  sort_order integer not null default 0,
  css_class text,
  evidence_key text,
  icon_bg text,
  icon text,
  label text,
  small_label text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.firm_meta_items (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  kind text not null,
  sort_order integer not null default 0,
  label text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.list_items (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  fund_id uuid references public.funds(id) on delete cascade,
  group_key text not null,
  sort_order integer not null default 0,
  name text,
  value text,
  note text,
  badge text,
  tone text,
  role_text text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.portfolio_metrics (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  fund_id uuid references public.funds(id) on delete cascade,
  metric_kind text not null,
  sort_order integer not null default 0,
  label text,
  examples text,
  width_label text,
  count_label text,
  color text,
  value_text text,
  value_numeric numeric,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.firm_ranks (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  place integer,
  tier text,
  of_count integer,
  is_example boolean not null default false,
  is_current boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.evidence_cards (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  evidence_key text not null,
  kicker text,
  title text,
  body text,
  tone text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (firm_id, evidence_key)
);

create table public.evidence_lines (
  id uuid primary key default gen_random_uuid(),
  card_id uuid not null references public.evidence_cards(id) on delete cascade,
  sort_order integer not null default 0,
  label text,
  value text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Scores
-- ---------------------------------------------------------------------------

create table public.score_versions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.score_sections (
  id uuid primary key default gen_random_uuid(),
  version_id uuid not null references public.score_versions(id) on delete cascade,
  code text not null,
  name text not null,
  max_points numeric,
  sort_order integer not null default 0,
  kind text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (version_id, code)
);

create table public.score_results (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  fund_id uuid references public.funds(id) on delete cascade,
  version_id uuid not null references public.score_versions(id),
  total numeric,
  total_shown numeric,
  band text,
  range_low numeric,
  range_high numeric,
  coverage_pct numeric,
  confidence text,
  is_current boolean not null default false,
  computed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.score_result_parts (
  id uuid primary key default gen_random_uuid(),
  result_id uuid not null references public.score_results(id) on delete cascade,
  section_code text not null,
  sort_order integer not null default 0,
  name text,
  legend text,
  got text,
  max_label text,
  legend_of text,
  rule_text text,
  aria text,
  card_class text,
  bar_class text,
  legend_class text,
  hero_flex text,
  hero_fill text,
  score_bar text,
  points_numeric numeric,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.score_lines (
  id uuid primary key default gen_random_uuid(),
  result_id uuid not null references public.score_results(id) on delete cascade,
  section_code text not null,
  sort_order integer not null default 0,
  name text,
  points_label text,
  why text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.score_inputs (
  id uuid primary key default gen_random_uuid(),
  result_id uuid not null references public.score_results(id) on delete cascade,
  section_code text not null,
  sort_order integer not null default 0,
  name text not null,
  value_numeric numeric,
  value_text text,
  max_numeric numeric,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Homepage feed and gating
-- ---------------------------------------------------------------------------

create table public.site_stats (
  id uuid primary key default gen_random_uuid(),
  sort_order integer not null default 0,
  n numeric not null,
  label text not null,
  detail text,
  verified boolean not null default false,
  unverified_label text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.site_updates (
  id uuid primary key default gen_random_uuid(),
  sort_order integer not null default 0,
  update_no integer,
  happened_on date,
  happened_label text,
  firm_id uuid references public.firms(id) on delete set null,
  firm_name text,
  kind text,
  body text,
  source_name text,
  url text,
  verification text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.gating_policies (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  anonymous_free_reports integer not null default 2,
  registered_extra_reports integer not null default 5,
  dwell_ms integer not null default 2000,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.report_views (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete cascade,
  anon_key text,
  firm_id uuid not null references public.firms(id) on delete cascade,
  source text,
  first_opened_at timestamptz not null default now(),
  last_opened_at timestamptz not null default now(),
  dwell_ms integer not null default 0,
  counted boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint report_views_who check (profile_id is not null or anon_key is not null)
);

create unique index report_views_account_firm
  on public.report_views (profile_id, firm_id)
  where profile_id is not null;

create unique index report_views_anon_firm
  on public.report_views (anon_key, firm_id)
  where anon_key is not null;

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

create index funds_firm_idx on public.funds (firm_id);
create index fund_entities_firm_idx on public.fund_entities (firm_id);
create index fund_entities_fund_idx on public.fund_entities (fund_id);
create index fund_people_firm_idx on public.fund_people (firm_id);
create index fund_people_person_idx on public.fund_people (person_id);
create index fund_people_fund_idx on public.fund_people (fund_id);
create index investments_firm_idx on public.investments (firm_id);
create index investments_fund_idx on public.investments (fund_id);
create index investments_company_idx on public.investments (company_id);
create index company_founders_company_idx on public.company_founders (company_id);
create index company_founders_person_idx on public.company_founders (person_id);
create index reviews_firm_idx on public.reviews (firm_id);
create index reviews_company_idx on public.reviews (company_id);
create index legal_matter_firms_firm_idx on public.legal_matter_firms (firm_id);
create index legal_matter_firms_matter_idx on public.legal_matter_firms (matter_id);
create index legal_matter_parties_matter_idx on public.legal_matter_parties (matter_id);
create index filings_matter_idx on public.filings (matter_id);
create index docket_entries_matter_idx on public.docket_entries (matter_id);
create index regulatory_records_firm_idx on public.regulatory_records (firm_id);
create index sanctions_checks_firm_idx on public.sanctions_checks (firm_id);
create index press_item_firms_firm_idx on public.press_item_firms (firm_id);
create index press_items_sentiment_idx on public.press_items (sentiment);
create index fact_sources_fact_idx on public.fact_sources (fact_type, fact_id);
create index fact_sources_source_idx on public.fact_sources (source_id);
create index fact_sources_firm_idx on public.fact_sources (firm_id);
create index takeaways_firm_idx on public.takeaways (firm_id);
create index ask_questions_firm_idx on public.ask_questions (firm_id);
create index score_results_firm_idx on public.score_results (firm_id, is_current);
create index score_inputs_result_idx on public.score_inputs (result_id);
create index evidence_cards_firm_idx on public.evidence_cards (firm_id);
create index firms_published_idx on public.firms (published, is_test);
create index report_views_firm_idx on public.report_views (firm_id);
create index portfolio_companies_name_idx on public.portfolio_companies (name);

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------

do $$
declare r record;
begin
  for r in
    select c.table_name
    from information_schema.columns c
    where c.table_schema = 'public' and c.column_name = 'updated_at'
  loop
    execute format('drop trigger if exists %I on public.%I', 'touch_' || r.table_name, r.table_name);
    execute format(
      'create trigger %I before update on public.%I for each row execute function public.touch_updated_at()',
      'touch_' || r.table_name, r.table_name
    );
  end loop;
end $$;

-- Methodology rows. Not firm data.
insert into public.score_versions (code, name, notes) values
  ('v2', 'Toxy Score v2', 'Agreed Oct 2, 2026. See docs/toxy-score-v2-rules.md.'),
  ('legacy-list', 'Toxy list score', 'Homepage score from the existing Toxy list. Not rescored on v2.');

insert into public.score_sections (version_id, code, name, max_points, sort_order, kind)
select v.id, s.code, s.name, s.max_points, s.sort_order, s.kind
from public.score_versions v
join (values
  ('s1', 'Fund vs. founders', 60, 1, 'base'),
  ('s2', 'Ability to support you', 17.5, 2, 'base'),
  ('s3', 'Founder experience', 17.5, 3, 'base'),
  ('s4', 'Conflicts of interest', 5, 4, 'base'),
  ('bonus', 'Track record bonus', 3, 5, 'bonus'),
  ('pen', 'Regulatory penalty', 50, 6, 'penalty')
) as s(code, name, max_points, sort_order, kind) on true
where v.code = 'v2';

insert into public.gating_policies (code, anonymous_free_reports, registered_extra_reports, dwell_ms)
values ('default', 2, 5, 2000);

-- Bundle the published site for the anon build. security invoker so RLS applies;
-- the WHERE clause also excludes test rows if the caller bypasses RLS.
create or replace function public.published_site_bundle()
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  with pub as (
    select id from firms where published and not is_test
  ),
  pub_matters as (
    select distinct matter_id as id
    from legal_matter_firms
    where firm_id in (select id from pub)
  ),
  pub_cards as (
    select id from evidence_cards where firm_id in (select id from pub)
  ),
  pub_sources as (
    select distinct source_id as id
    from fact_sources
    where firm_id in (select id from pub)
  ),
  pub_people as (
    select person_id as id from fund_people where firm_id in (select id from pub)
    union
    select founder_person_id from reviews where firm_id in (select id from pub) and founder_person_id is not null
    union
    select partner_person_id from reviews where firm_id in (select id from pub) and partner_person_id is not null
    union
    select board_person_id from investments where firm_id in (select id from pub) and board_person_id is not null
    union
    select cf.person_id
    from company_founders cf
    join investments i on i.company_id = cf.company_id
    where i.firm_id in (select id from pub)
  ),
  pub_companies as (
    select distinct company_id as id from investments where firm_id in (select id from pub)
  ),
  pub_press as (
    select press_item_id as id from press_item_firms where firm_id in (select id from pub)
  ),
  pub_results as (
    select id from score_results where firm_id in (select id from pub)
  ),
  pub_reviews as (
    select id from reviews where firm_id in (select id from pub)
  )
  select jsonb_build_object(
    'firms', coalesce((select jsonb_agg(to_jsonb(t) order by t.list_sort, t.slug) from firms t where t.id in (select id from pub)), '[]'::jsonb),
    'funds', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order, t.name) from funds t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'fund_entities', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from fund_entities t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'people', coalesce((select jsonb_agg(to_jsonb(t) order by t.full_name) from people t where t.id in (select id from pub_people)), '[]'::jsonb),
    'fund_people', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from fund_people t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'portfolio_companies', coalesce((select jsonb_agg(to_jsonb(t) order by t.name) from portfolio_companies t where t.id in (select id from pub_companies)), '[]'::jsonb),
    'company_founders', coalesce((select jsonb_agg(to_jsonb(t)) from company_founders t where t.company_id in (select id from pub_companies)), '[]'::jsonb),
    'investments', coalesce((select jsonb_agg(to_jsonb(t)) from investments t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'reviews', coalesce((select jsonb_agg(to_jsonb(t) order by t.reviewed_on nulls last, t.created_at) from reviews t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'review_ratings', coalesce((select jsonb_agg(to_jsonb(t)) from review_ratings t where t.review_id in (select id from pub_reviews)), '[]'::jsonb),
    'legal_matters', coalesce((select jsonb_agg(to_jsonb(t)) from legal_matters t where t.id in (select id from pub_matters)), '[]'::jsonb),
    'legal_matter_firms', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from legal_matter_firms t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'legal_matter_parties', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from legal_matter_parties t where t.matter_id in (select id from pub_matters)), '[]'::jsonb),
    'filings', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from filings t where t.matter_id in (select id from pub_matters)), '[]'::jsonb),
    'docket_entries', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from docket_entries t where t.matter_id in (select id from pub_matters)), '[]'::jsonb),
    'legal_groups', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from legal_groups t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'legal_group_items', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from legal_group_items t where t.group_id in (select id from legal_groups where firm_id in (select id from pub))), '[]'::jsonb),
    'regulatory_records', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from regulatory_records t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'sanctions_checks', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from sanctions_checks t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'press_items', coalesce((select jsonb_agg(to_jsonb(t)) from press_items t where t.id in (select id from pub_press)), '[]'::jsonb),
    'press_item_firms', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from press_item_firms t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'sources', coalesce((select jsonb_agg(to_jsonb(t)) from sources t where t.id in (select id from pub_sources)), '[]'::jsonb),
    'fact_sources', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from fact_sources t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'takeaways', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from takeaways t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'ask_questions', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from ask_questions t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'copy_blocks', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from copy_blocks t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'page_chips', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from page_chips t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'firm_meta_items', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from firm_meta_items t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'list_items', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from list_items t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'portfolio_metrics', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from portfolio_metrics t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'firm_ranks', coalesce((select jsonb_agg(to_jsonb(t)) from firm_ranks t where t.firm_id in (select id from pub) and t.is_current), '[]'::jsonb),
    'evidence_cards', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from evidence_cards t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'evidence_lines', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from evidence_lines t where t.card_id in (select id from pub_cards)), '[]'::jsonb),
    'score_versions', coalesce((select jsonb_agg(to_jsonb(t)) from score_versions t), '[]'::jsonb),
    'score_sections', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from score_sections t), '[]'::jsonb),
    'score_results', coalesce((select jsonb_agg(to_jsonb(t)) from score_results t where t.id in (select id from pub_results)), '[]'::jsonb),
    'score_result_parts', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from score_result_parts t where t.result_id in (select id from pub_results)), '[]'::jsonb),
    'score_lines', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from score_lines t where t.result_id in (select id from pub_results)), '[]'::jsonb),
    'score_inputs', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from score_inputs t where t.result_id in (select id from pub_results)), '[]'::jsonb),
    'site_stats', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from site_stats t), '[]'::jsonb),
    'site_updates', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from site_updates t), '[]'::jsonb)
  );
$$;
