-- Failed payments: invoice.payment_failed marks the plan past_due; if it isn't paid within 24h the hourly
-- downgrade-lapsed-payments job drops it to free. invoice.paid clears it (grant_checks restores the plan).
-- Backup: _bak_check_balances_20261023.
alter table public.check_balances add column if not exists past_due_since timestamptz;

create or replace function public.mark_past_due(p_sub text) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  update check_balances set past_due_since = coalesce(past_due_since, now()), updated_at = now()
    where stripe_subscription_id = p_sub and plan is not null;
  get diagnostics n = row_count; return n;
end $$;

create or replace function public.clear_past_due(p_sub text) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  update check_balances set past_due_since = null, updated_at = now() where stripe_subscription_id = p_sub and past_due_since is not null;
  get diagnostics n = row_count; return n;
end $$;

-- Same job as before (legacy subscriptions table) plus the launch balances: past_due for 24h -> free plan.
-- stripe_subscription_id is kept so a late invoice.paid restores the plan through grant_checks.
create or replace function public.downgrade_lapsed_payments() returns integer
language plpgsql security definer set search_path = public as $$
declare n integer; m integer;
begin
  update public.subscriptions set status = 'unpaid'
    where status = 'active' and payment_failed_at is not null and payment_failed_at <= now() - interval '24 hours';
  get diagnostics n = row_count;
  update public.check_balances set plan = null, monthly_checks = null, next_refill = null, plan_name = null,
      cancel_at_period_end = false, past_due_since = null, updated_at = now()
    where past_due_since is not null and past_due_since <= now() - interval '24 hours' and plan is not null;
  get diagnostics m = row_count;
  return n + m;
end $$;

revoke all on function public.mark_past_due(text), public.clear_past_due(text), public.downgrade_lapsed_payments() from public, anon, authenticated;
grant execute on function public.mark_past_due(text), public.clear_past_due(text), public.downgrade_lapsed_payments() to service_role;
