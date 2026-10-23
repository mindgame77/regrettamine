-- Regretamin launch: check balances, check events, unlock RPCs, unknown-firm queue.
-- NOT applied to production yet. Back up first (supabase db dump) and report before applying.
-- Counting is in checks: anonymous 2, +4 on sign-up, plans add 10/30 per period, single adds 1.

create table if not exists public.check_balances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users(id) on delete cascade,
  anon_id uuid unique,
  free_left int not null default 2 check (free_left >= 0),
  paid_left int not null default 0 check (paid_left >= 0),
  plan text check (plan in ('m10','m30')),
  period_end timestamptz,
  stripe_customer_id text unique,
  stripe_subscription_id text,
  signup_bonus_given boolean not null default false,
  updated_at timestamptz not null default now(),
  check (user_id is not null or anon_id is not null)
);

create table if not exists public.check_events (
  id bigint generated always as identity primary key,
  balance_id uuid not null references public.check_balances(id) on delete cascade,
  firm_id uuid references public.firms(id),
  kind text not null check (kind in ('spend_free','spend_paid','grant_signup','grant_single','grant_plan')),
  amount int not null,
  stripe_event_id text unique,
  created_at timestamptz not null default now()
);
create index if not exists check_events_firm on public.check_events(balance_id, firm_id);

create table if not exists public.check_requests (
  id bigint generated always as identity primary key,
  query text not null check (length(query) between 1 and 200),
  email text check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  anon_id uuid,
  user_id uuid references auth.users(id) on delete set null,
  status text not null default 'queued' check (status in ('queued','running','done','failed','no_match')),
  firm_id uuid references public.firms(id),
  notified_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists check_requests_status on public.check_requests(status, created_at);

alter table public.check_balances enable row level security;
alter table public.check_events enable row level security;
alter table public.check_requests enable row level security;
-- No direct client policies: all access goes through the security definer functions below.

create or replace function public._balance(p_anon uuid) returns public.check_balances
language plpgsql security definer set search_path = public as $$
declare b public.check_balances;
begin
  if auth.uid() is not null then
    select * into b from check_balances where user_id = auth.uid() for update;
    if not found then insert into check_balances(user_id) values (auth.uid()) returning * into b; end if;
    if not b.signup_bonus_given then
      update check_balances set free_left = free_left + 4, signup_bonus_given = true, updated_at = now() where id = b.id returning * into b;
      insert into check_events(balance_id, kind, amount) values (b.id, 'grant_signup', 4);
    end if;
  else
    if p_anon is null then raise exception 'anon id required'; end if;
    select * into b from check_balances where anon_id = p_anon and user_id is null for update;
    if not found then insert into check_balances(anon_id) values (p_anon) returning * into b; end if;
  end if;
  return b;
end $$;
revoke all on function public._balance(uuid) from public, anon, authenticated;

create or replace function public.check_balance(p_anon uuid) returns json
language plpgsql security definer set search_path = public as $$
declare b public.check_balances := _balance(p_anon);
begin return json_build_object('left', b.free_left + b.paid_left, 'signed_in', auth.uid() is not null); end $$;

-- Merge an anonymous balance's history into the signed-in user (free checks used stay used).
create or replace function public.claim_anon_checks(p_anon uuid) returns void
language plpgsql security definer set search_path = public as $$
declare a public.check_balances; b public.check_balances;
begin
  if auth.uid() is null then return; end if;
  b := _balance(null);
  select * into a from check_balances where anon_id = p_anon and user_id is null for update;
  if not found then return; end if;
  update check_events set balance_id = b.id where balance_id = a.id;
  update check_balances set free_left = least(free_left, a.free_left + 4) where id = b.id;
  delete from check_balances where id = a.id;
end $$;

-- use_check: spend 1 check on a firm (re-opening an unlocked firm is free). Returns status + details.
create or replace function public.unlock_firm(p_slug text, p_anon uuid, p_spend boolean default true) returns json
language plpgsql security definer set search_path = public as $$
declare b public.check_balances := _balance(p_anon); f uuid;
begin
  select id into f from firms where slug = p_slug and deleted_at is null and published;
  if f is null then return json_build_object('status','not_found'); end if;
  if not exists (select 1 from check_events where balance_id = b.id and firm_id = f and kind like 'spend_%') then
    if not p_spend then return json_build_object('status','locked'); end if;
    if b.free_left > 0 then
      update check_balances set free_left = free_left - 1, updated_at = now() where id = b.id;
      insert into check_events(balance_id, firm_id, kind, amount) values (b.id, f, 'spend_free', -1);
    elsif b.paid_left > 0 then
      update check_balances set paid_left = paid_left - 1, updated_at = now() where id = b.id;
      insert into check_events(balance_id, firm_id, kind, amount) values (b.id, f, 'spend_paid', -1);
    elsif auth.uid() is null then return json_build_object('status','need_signup');
    else return json_build_object('status','out');
    end if;
  end if;
  return json_build_object('status','ok','details', public.firm_details(f));
end $$;

-- Placeholder: details payload per row. Real rendering of sources moves here from the static build.
create or replace function public.firm_details(p_firm uuid) returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('row', 0, 'html', '')), '[]'::json) where false
$$;
revoke all on function public.firm_details(uuid) from public, anon, authenticated;

create or replace function public.request_check(p_query text, p_email text, p_anon uuid) returns void
language sql security definer set search_path = public as $$
  insert into check_requests(query, email, anon_id, user_id) values (trim(p_query), nullif(trim(p_email),''), p_anon, auth.uid());
$$;

-- Called only by the Stripe webhook (service role).
create or replace function public.grant_checks(p_user uuid, p_kind text, p_amount int, p_event text, p_plan text default null, p_period_end timestamptz default null, p_customer text default null, p_sub text default null) returns void
language plpgsql security definer set search_path = public as $$
declare b public.check_balances;
begin
  if exists (select 1 from check_events where stripe_event_id = p_event) then return; end if;
  insert into check_balances(user_id, signup_bonus_given, free_left) values (p_user, true, 6) on conflict (user_id) do nothing;
  update check_balances set
    paid_left = case when p_kind = 'grant_plan' then p_amount + (case when plan is null then paid_left else 0 end) else paid_left + p_amount end,
    plan = coalesce(p_plan, plan), period_end = coalesce(p_period_end, period_end),
    stripe_customer_id = coalesce(p_customer, stripe_customer_id), stripe_subscription_id = coalesce(p_sub, stripe_subscription_id), updated_at = now()
  where user_id = p_user returning * into b;
  insert into check_events(balance_id, kind, amount, stripe_event_id) values (b.id, p_kind, p_amount, p_event);
end $$;
revoke all on function public.grant_checks(uuid,text,int,text,text,timestamptz,text,text) from public, anon, authenticated;

grant execute on function public.check_balance(uuid), public.claim_anon_checks(uuid), public.unlock_firm(text,uuid,boolean), public.request_check(text,text,uuid) to anon, authenticated;
