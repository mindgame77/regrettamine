-- Yearly plans (y10/y30) and code-unlocked hidden plans ('custom'): checks refill monthly.
-- Backup: /workspace/toxybase/backups/2026-10-22-yearly-codes (tag pre-yearly-codes).
alter table public.check_balances
  add column monthly_checks integer check (monthly_checks > 0),  -- checks per month for yearly/custom plans (refill amount)
  add column next_refill timestamptz,                             -- next monthly refill; null for monthly plans (Stripe invoice refills those)
  add column plan_name text;                                      -- display name of a 'custom' (code-unlocked) plan
alter table public.check_balances drop constraint check_balances_plan_check;
alter table public.check_balances add constraint check_balances_plan_check check (plan in ('m10', 'm30', 'y10', 'y30', 'custom'));
alter table public.check_events drop constraint check_events_kind_check;
alter table public.check_events add constraint check_events_kind_check
  check (kind in ('spend_free', 'spend_paid', 'grant_signup', 'grant_single', 'grant_plan', 'grant_refill'));

drop function public.grant_checks(uuid, text, integer, text, text, timestamptz, text, text);
create function public.grant_checks(p_user uuid, p_kind text, p_amount integer, p_event text, p_plan text default null,
  p_period_end timestamptz default null, p_customer text default null, p_sub text default null,
  p_monthly integer default null, p_next_refill timestamptz default null, p_plan_name text default null)
returns void language plpgsql security definer set search_path = public as $$
declare b public.check_balances;
begin
  if exists (select 1 from check_events where stripe_event_id = p_event) then return; end if;
  insert into check_balances(user_id, signup_bonus_given, free_left) values (p_user, true, 6) on conflict (user_id) do nothing;
  update check_balances set
    paid_left = case when p_kind = 'grant_plan' then p_amount + (case when plan is null then paid_left else 0 end) else paid_left + p_amount end,
    plan = coalesce(p_plan, plan), period_end = coalesce(p_period_end, period_end),
    stripe_customer_id = coalesce(p_customer, stripe_customer_id), stripe_subscription_id = coalesce(p_sub, stripe_subscription_id),
    monthly_checks = case when p_kind = 'grant_plan' then p_monthly else monthly_checks end,
    next_refill = case when p_kind = 'grant_plan' then p_next_refill else next_refill end,
    plan_name = case when p_kind = 'grant_plan' then p_plan_name else plan_name end,
    updated_at = now()
  where user_id = p_user returning * into b;
  insert into check_events(balance_id, kind, amount, stripe_event_id) values (b.id, p_kind, p_amount, p_event);
end $$;
revoke all on function public.grant_checks(uuid, text, integer, text, text, timestamptz, text, text, integer, timestamptz, text) from public, anon, authenticated;

-- Monthly refill for yearly/custom plans: set paid checks to the plan's monthly amount (like a monthly invoice does).
create function public.refill_yearly_checks() returns integer language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0;
begin
  for r in select * from check_balances where plan is not null and next_refill is not null and next_refill <= now()
           and monthly_checks is not null and (period_end is null or period_end > now()) for update loop
    update check_balances set paid_left = r.monthly_checks,
      next_refill = r.next_refill + interval '1 month',  -- if several months behind, later hourly runs catch up (sets, never adds)
      updated_at = now() where id = r.id;
    insert into check_events(balance_id, kind, amount) values (r.id, 'grant_refill', r.monthly_checks);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.refill_yearly_checks() from public, anon, authenticated;
select cron.schedule('regretamin-refill-yearly', '7 * * * *', 'select public.refill_yearly_checks()');

create or replace function public.my_account() returns json language plpgsql security definer set search_path = public as $$
declare b public.check_balances;
begin
  if auth.uid() is null then return null; end if;
  b := _balance(null);
  return json_build_object('plan', b.plan, 'left', b.free_left + b.paid_left, 'paid_left', b.paid_left,
    'period_end', b.period_end, 'cancel_at_period_end', b.cancel_at_period_end, 'has_customer', b.stripe_customer_id is not null
      or exists (select 1 from subscriptions s where s.profile_id = auth.uid() and s.stripe_customer_id is not null),
    'monthly_checks', b.monthly_checks, 'next_refill', b.next_refill, 'plan_name', b.plan_name);
end $$;
