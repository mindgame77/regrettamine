-- Accounts, watchlist, alert preferences, and founder reviews.
-- Apply after 20261004120100_rls.sql. Does not insert user rows.

-- ---------------------------------------------------------------------------
-- Profile + default alert prefs when an auth user is created
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  meta jsonb := '{}'::jsonb;
  label text;
begin
  if to_jsonb(new) ? 'raw_user_meta_data' then
    meta := coalesce(to_jsonb(new) -> 'raw_user_meta_data', '{}'::jsonb);
  end if;
  label := coalesce(
    meta->>'full_name',
    meta->>'name',
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'member'
  );
  insert into public.profiles (id, display_name)
  values (new.id, label)
  on conflict (id) do nothing;
  insert into public.alert_preferences (profile_id)
  values (new.id)
  on conflict (profile_id) do nothing;
  return new;
end;
$$;

-- Signup runs as the auth admin role on Supabase, which must be allowed to fire the trigger.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    grant execute on function public.handle_new_user() to supabase_auth_admin;
  end if;
end $$;

create table public.alert_preferences (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  new_legal_matter boolean not null default true,
  regulatory_record boolean not null default true,
  partner_exit boolean not null default false,
  score_change boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Watchlist. One row per (person, firm). Hard cap of 100.
-- ---------------------------------------------------------------------------

create table public.watchlist (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  firm_id uuid not null references public.firms(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (profile_id, firm_id)
);

create index watchlist_firm_idx on public.watchlist (firm_id);

create or replace function public.watchlist_cap()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (
    select count(*) from public.watchlist w
    where w.profile_id = new.profile_id
  ) >= 100 then
    raise exception 'watchlist full (100/100)' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger watchlist_cap
  before insert on public.watchlist
  for each row execute function public.watchlist_cap();

-- ---------------------------------------------------------------------------
-- Reviews written by a signed-in founder. Pending until a moderator approves.
-- ---------------------------------------------------------------------------

alter table public.reviews
  add column profile_id uuid references public.profiles(id) on delete set null,
  add column anonymous boolean not null default true,
  add column role_label text,
  add column round_label text,
  add column would_again boolean,
  add column verification_method text;

alter table public.reviews
  drop constraint if exists reviews_verification_method_check;

alter table public.reviews
  add constraint reviews_verification_method_check
  check (verification_method is null or verification_method in ('work_email', 'linkedin', 'cap_table'));

create index reviews_profile_idx on public.reviews (profile_id);

-- Public pages only show approved reviews. The author can still read their own pending row.
drop policy if exists reviews_public_read on public.reviews;
create policy reviews_public_read on public.reviews
  for select to anon, authenticated
  using (public.firm_is_public(firm_id) and moderation_status = 'approved');

create policy reviews_owner_read on public.reviews
  for select to authenticated
  using (profile_id = auth.uid());

create policy reviews_owner_insert on public.reviews
  for insert to authenticated
  with check (
    profile_id = auth.uid()
    and moderation_status = 'pending'
    and public.firm_is_public(firm_id)
  );

drop policy if exists review_ratings_public_read on public.review_ratings;
create policy review_ratings_public_read on public.review_ratings
  for select to anon, authenticated
  using (exists (
    select 1 from public.reviews r
    where r.id = review_ratings.review_id
      and public.firm_is_public(r.firm_id)
      and r.moderation_status = 'approved'
  ));

create policy review_ratings_owner_read on public.review_ratings
  for select to authenticated
  using (exists (
    select 1 from public.reviews r
    where r.id = review_ratings.review_id and r.profile_id = auth.uid()
  ));

create policy review_ratings_owner_insert on public.review_ratings
  for insert to authenticated
  with check (exists (
    select 1 from public.reviews r
    where r.id = review_ratings.review_id
      and r.profile_id = auth.uid()
      and r.moderation_status = 'pending'
  ));

-- ---------------------------------------------------------------------------
-- Own-row access for the new tables. Report views already have owner policies.
-- ---------------------------------------------------------------------------

alter table public.alert_preferences enable row level security;
alter table public.watchlist enable row level security;

create policy alert_preferences_own on public.alert_preferences
  for all to authenticated
  using (profile_id = auth.uid() or public.is_admin())
  with check (profile_id = auth.uid() or public.is_admin());

create policy watchlist_own on public.watchlist
  for all to authenticated
  using (profile_id = auth.uid() or public.is_admin())
  with check (
    (profile_id = auth.uid() and public.firm_is_public(firm_id))
    or public.is_admin()
  );

grant select, insert, update, delete on public.watchlist to authenticated;
grant select, insert, update, delete on public.alert_preferences to authenticated;
revoke all on public.watchlist from anon;
revoke all on public.alert_preferences from anon;

create trigger touch_alert_preferences
  before update on public.alert_preferences
  for each row execute function public.touch_updated_at();
