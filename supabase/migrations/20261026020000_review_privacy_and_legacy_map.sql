-- Step 2 of the activity work.
-- 1. Signed-in users can no longer read another person's profile_id or
--    linkedin_url on reviews. Authors read their own through my_review_private().
-- 2. activity_legacy_map records which old row (founder_accounts,
--    vc_source_facts, research_submissions records, funds) now lives in which
--    new row. Nothing old is marked or deleted here.

-- 1. reviews privacy ---------------------------------------------------------
revoke select (profile_id) on public.reviews from authenticated;
revoke select (linkedin_url) on public.reviews from authenticated;

create or replace function public.my_review_private()
returns table (id uuid, profile_id uuid, linkedin_url text)
language sql
stable
security definer
set search_path = public
as $$
  select r.id, r.profile_id, r.linkedin_url
  from public.reviews r
  where auth.uid() is not null
    and r.profile_id = auth.uid();
$$;

revoke all on function public.my_review_private() from public, anon;
grant execute on function public.my_review_private() to authenticated;

-- review_ratings owner policies looked up reviews.profile_id as the caller.
-- They now ask a definer helper, so the column revoke above does not break them.
create or replace function public.owns_review(rid uuid, pending_only boolean default false)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.reviews r
    where r.id = rid
      and auth.uid() is not null
      and r.profile_id = auth.uid()
      and (not pending_only or r.moderation_status = 'pending')
  );
$$;

revoke all on function public.owns_review(uuid, boolean) from public, anon;
grant execute on function public.owns_review(uuid, boolean) to authenticated;

drop policy if exists review_ratings_owner_read on public.review_ratings;
create policy review_ratings_owner_read on public.review_ratings
  for select to authenticated
  using (public.owns_review(review_id));

drop policy if exists review_ratings_owner_insert on public.review_ratings;
create policy review_ratings_owner_insert on public.review_ratings
  for insert to authenticated
  with check (public.owns_review(review_id, true));

-- 2. old row -> new row map --------------------------------------------------
create table if not exists public.activity_legacy_map (
  id bigserial primary key,
  firm_id uuid not null references public.firms(id) on delete cascade,
  old_table text not null,
  old_id text not null,
  old_ref text,
  new_table text,
  new_id uuid,
  relation text not null check (relation in ('moved', 'merged', 'not_moved')),
  note text,
  created_at timestamptz not null default now(),
  unique (old_table, old_id, new_table, new_id)
);

alter table public.activity_legacy_map enable row level security;
revoke all on public.activity_legacy_map from anon, authenticated;
