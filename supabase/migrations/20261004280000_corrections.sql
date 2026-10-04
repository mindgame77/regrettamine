-- Paid users can ask for a correction. Admins review the queue.
-- fund_id is the public fund, which is a firms row.

create table public.corrections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  fund_id uuid not null references public.firms(id) on delete cascade,
  page_url text not null,
  message text not null,
  source_url text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  constraint corrections_status_check check (status in ('pending', 'approved', 'rejected')),
  constraint corrections_message_check check (char_length(btrim(message)) between 1 and 4000),
  constraint corrections_page_url_check check (page_url ~* '^https?://'),
  constraint corrections_source_url_check check (source_url ~* '^https?://')
);

create index corrections_status_idx on public.corrections (status, created_at desc);

alter table public.corrections enable row level security;
alter table public.corrections force row level security;

revoke all on table public.corrections from public, anon;
grant select, insert, update on table public.corrections to authenticated;
grant select, insert, update, delete on table public.corrections to service_role;

create policy corrections_select on public.corrections
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

create policy corrections_insert_paid on public.corrections
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and status = 'pending'
    and public.is_paid(auth.uid())
    and public.firm_is_public(fund_id)
  );

create policy corrections_admin_update on public.corrections
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- The firms table is not readable from the browser. This returns the id of a
-- published fund so the insert can still go through the paid-only policy.
create or replace function public.public_firm_id(p_slug text)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id
  from public.firms
  where slug = p_slug
    and published
    and not is_test;
$$;

revoke all on function public.public_firm_id(text) from public;
grant execute on function public.public_firm_id(text) to authenticated, service_role;
