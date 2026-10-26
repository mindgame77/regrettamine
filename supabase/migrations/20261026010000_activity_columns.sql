-- Step 1 of the activity import: one home per kind of data.
--   reviews     = founder reviews (and other voices, kept non-public)
--   investments = deals (company row in portfolio_companies)
--   funds       = fund raises / closes
-- Additive only: new nullable columns, unique dedupe indexes, and a tighter
-- public read rule on reviews. No column is dropped, renamed or rewritten.

-- reviews ------------------------------------------------------------------
alter table public.reviews
  add column if not exists date_precision text,      -- day / month / year / unknown
  add column if not exists author_name    text,      -- role stays in role_label
  add column if not exists source_urls    text[],    -- one or more links
  add column if not exists review_type    text,      -- founder / employee / firm_voice / company / aggregator
  add column if not exists independent    boolean,
  add column if not exists is_public      boolean,   -- null = not public
  add column if not exists conflict_flags text[],
  add column if not exists dedupe_key     text,
  add column if not exists source_system  text;

do $$ begin
  alter table public.reviews add constraint reviews_review_type_check
    check (review_type is null or review_type in ('founder','employee','firm_voice','company','aggregator'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.reviews add constraint reviews_date_precision_check
    check (date_precision is null or date_precision in ('day','month','year','unknown'));
exception when duplicate_object then null; end $$;

create unique index if not exists reviews_dedupe_uq
  on public.reviews (firm_id, dedupe_key) where dedupe_key is not null;

-- investments --------------------------------------------------------------
alter table public.investments
  add column if not exists date_precision text,
  add column if not exists amount         numeric,
  add column if not exists currency       text,
  add column if not exists role           text,      -- lead / participant / unknown (is_lead kept as is)
  add column if not exists source_urls    text[],
  add column if not exists verified       boolean,
  add column if not exists conflict_flags text[],
  add column if not exists dedupe_key     text,
  add column if not exists source_system  text;

do $$ begin
  alter table public.investments add constraint investments_role_check
    check (role is null or role in ('lead','participant','unknown'));
exception when duplicate_object then null; end $$;

create unique index if not exists investments_dedupe_uq
  on public.investments (firm_id, dedupe_key) where dedupe_key is not null;

-- funds --------------------------------------------------------------------
alter table public.funds
  add column if not exists raised_usd     numeric,   -- size_usd kept; raised vs target split out
  add column if not exists target_usd     numeric,
  add column if not exists close_status   text,      -- raising / first_close / final_close / raised / offering
  add column if not exists closed_on      date,
  add column if not exists date_precision text,
  add column if not exists filing_url     text,
  add column if not exists source_urls    text[],
  add column if not exists verified       boolean,
  add column if not exists conflict_flags text[],
  add column if not exists dedupe_key     text;

do $$ begin
  alter table public.funds add constraint funds_close_status_check
    check (close_status is null or close_status in ('raising','first_close','final_close','raised','offering'));
exception when duplicate_object then null; end $$;

create unique index if not exists funds_dedupe_uq
  on public.funds (firm_id, dedupe_key) where dedupe_key is not null;

-- per-firm coverage: {checked_at, window_from, window_to, sources[], rounds}
alter table public.firms add column if not exists activity_coverage jsonb;

-- reviews read rule ----------------------------------------------------------
-- Visitors see only public, approved founder reviews on public firms.
drop policy if exists reviews_public_read on public.reviews;
create policy reviews_public_read on public.reviews
  for select to anon, authenticated
  using (public.firm_is_public(firm_id)
         and moderation_status in ('approved','published')
         and is_public is true
         and review_type = 'founder');

-- Signed-out visitors never get profile_id (linkedin_url was never granted).
revoke select (profile_id) on public.reviews from anon;
revoke select (linkedin_url) on public.reviews from anon;

grant select (date_precision, author_name, source_urls, review_type, independent, is_public)
  on public.reviews to anon, authenticated;
