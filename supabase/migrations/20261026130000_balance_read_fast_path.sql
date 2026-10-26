-- Speed: page loads (check_balance, my_account) no longer insert + SELECT ... FOR UPDATE on every call.
-- When the balance row already exists (and, signed in, the signup bonus was given) it is a plain read.
-- Otherwise it falls back to _balance(), which creates the row / grants the bonus exactly as before.
-- Spending paths (unlock_firm, firm_activity_list) keep calling _balance() with its row lock.
create or replace function public._balance_read(p_anon uuid)
 returns check_balances
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare b public.check_balances;
begin
  if auth.uid() is not null then
    select * into b from check_balances where user_id = auth.uid();
    if found and b.signup_bonus_given then return b; end if;
  elsif p_anon is not null then
    select * into b from check_balances where anon_id = p_anon and user_id is null;
    if found then return b; end if;
  end if;
  return _balance(p_anon);
end $function$;
revoke all on function public._balance_read(uuid) from public, anon, authenticated;

create or replace function public.check_balance(p_anon uuid)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare b public.check_balances := _balance_read(p_anon);
begin return json_build_object('left', b.free_left + b.paid_left, 'signed_in', auth.uid() is not null); end $function$;

create or replace function public.my_account()
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare b public.check_balances;
begin
  if auth.uid() is null then return null; end if;
  b := _balance_read(null);
  return json_build_object('plan', b.plan, 'left', b.free_left + b.paid_left, 'paid_left', b.paid_left,
    'period_end', b.period_end, 'cancel_at_period_end', b.cancel_at_period_end, 'has_customer', b.stripe_customer_id is not null
      or exists (select 1 from subscriptions s where s.profile_id = auth.uid() and s.stripe_customer_id is not null),
    'monthly_checks', b.monthly_checks, 'next_refill', b.next_refill, 'plan_name', b.plan_name);
end $function$;
