-- Regretamin launch: cancel / resume subscription, exit reasons for cancel and delete.
-- check_balances keeps Stripe's cancel_at_period_end; period_end (already there) is the date the plan renews or ends.
alter table public.check_balances add column if not exists cancel_at_period_end boolean not null default false;

-- Anonymous exit answers: no user_id or email. Written only by the cancel-subscription and delete-account edge functions (service role).
create table if not exists public.exit_reasons (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('cancel', 'delete')),
  reason text check (reason in ('got_what_i_needed', 'too_expensive', 'didnt_find_my_vc', 'data_not_useful', 'other')),
  other_text text check (char_length(other_text) <= 500),
  plan text,
  created_at timestamptz not null default now()
);
alter table public.exit_reasons enable row level security;
revoke all on table public.exit_reasons from public, anon, authenticated;

-- Account page: plan, checks left, renewal/end date, cancel state, whether a Stripe customer exists.
create or replace function public.my_account() returns json
language plpgsql security definer set search_path = public as $$
declare b public.check_balances;
begin
  if auth.uid() is null then return null; end if;
  b := _balance(null);
  return json_build_object('plan', b.plan, 'left', b.free_left + b.paid_left, 'paid_left', b.paid_left,
    'period_end', b.period_end, 'cancel_at_period_end', b.cancel_at_period_end, 'has_customer', b.stripe_customer_id is not null
      or exists (select 1 from subscriptions s where s.profile_id = auth.uid() and s.stripe_customer_id is not null));
end $$;
revoke all on function public.my_account() from public, anon;
grant execute on function public.my_account() to authenticated;
