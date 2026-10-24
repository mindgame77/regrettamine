-- Credits: signed-out visitors get 2 free checks; a new account starts fresh with 4 (grant_signup +4).
-- Nothing moves at sign-in: claim_anon_checks becomes a no-op (kept so old cached clients don't error).
-- Existing balances and check_events are not touched.
create or replace function public._balance(p_anon uuid) returns public.check_balances
language plpgsql security definer set search_path = public as $$
declare b public.check_balances;
begin
  if auth.uid() is not null then
    insert into check_balances(user_id, free_left) values (auth.uid(), 0) on conflict (user_id) do nothing;
    select * into b from check_balances where user_id = auth.uid() for update;
    if not b.signup_bonus_given then
      update check_balances set free_left = free_left + 4, signup_bonus_given = true, updated_at = now() where id = b.id returning * into b;
      insert into check_events(balance_id, kind, amount) values (b.id, 'grant_signup', 4);
    end if;
  else
    if p_anon is null then raise exception 'anon id required'; end if;
    insert into check_balances(anon_id) values (p_anon) on conflict (anon_id) do nothing;
    select * into b from check_balances where anon_id = p_anon and user_id is null for update;
  end if;
  return b;
end $$;
revoke all on function public._balance(uuid) from public, anon, authenticated;

create or replace function public.claim_anon_checks(p_anon uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  return; -- no-op: anon credits and unlocks stay with the anon id
end $$;

-- A Stripe grant for a user with no balance row yet also starts from the same fresh 4 (was 6).
create or replace function public.grant_checks(p_user uuid, p_kind text, p_amount integer, p_event text, p_plan text default null,
  p_period_end timestamptz default null, p_customer text default null, p_sub text default null,
  p_monthly integer default null, p_next_refill timestamptz default null, p_plan_name text default null)
returns void language plpgsql security definer set search_path = public as $$
declare b public.check_balances;
begin
  if exists (select 1 from check_events where stripe_event_id = p_event) then return; end if;
  insert into check_balances(user_id, signup_bonus_given, free_left) values (p_user, true, 4) on conflict (user_id) do nothing;
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
