-- Stripe Payment Links. The browser never sees a secret.
-- The webhook function reads app_secrets.key = 'stripe_webhook_secret'
-- with the service role. RLS is on and there are no policies.

create table public.app_secrets (
  key text primary key,
  value text not null
);

alter table public.app_secrets enable row level security;
alter table public.app_secrets force row level security;
revoke all on table public.app_secrets from public, anon, authenticated;
grant select, insert, update, delete on table public.app_secrets to service_role;

comment on table public.app_secrets is
  'Private key/value secrets. No policies: only the service role (and the webhook) can read them.';

-- profile_id is the auth user id (Payment Link client_reference_id).
-- user_id mirrors it so the Stripe columns match the billing model.
alter table public.subscriptions
  add column if not exists user_id uuid generated always as (profile_id) stored,
  add column if not exists stripe_customer_id text,
  add column if not exists stripe_subscription_id text,
  add column if not exists price_id text,
  add column if not exists payment_failed_at timestamptz;

create unique index if not exists subscriptions_stripe_customer_uidx
  on public.subscriptions (stripe_customer_id)
  where stripe_customer_id is not null;

create unique index if not exists subscriptions_stripe_subscription_uidx
  on public.subscriptions (stripe_subscription_id)
  where stripe_subscription_id is not null;

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  user_id uuid generated always as (profile_id) stored,
  stripe_invoice_id text,
  stripe_checkout_session_id text,
  amount integer not null,
  currency text not null,
  status text not null,
  description text,
  receipt_url text,
  created_at timestamptz not null default now()
);

create unique index payments_invoice_uidx
  on public.payments (stripe_invoice_id)
  where stripe_invoice_id is not null;

create unique index payments_session_uidx
  on public.payments (stripe_checkout_session_id)
  where stripe_checkout_session_id is not null;

create index payments_profile_idx on public.payments (profile_id, created_at desc);

alter table public.payments enable row level security;

create policy payments_select_own on public.payments
  for select to authenticated
  using (profile_id = auth.uid());

revoke all on table public.payments from public, anon, authenticated;
grant select on table public.payments to authenticated;
grant select, insert, update, delete on table public.payments to service_role;

create table public.stripe_events (
  id text primary key,
  received_at timestamptz not null default now()
);

alter table public.stripe_events enable row level security;
alter table public.stripe_events force row level security;
revoke all on table public.stripe_events from public, anon, authenticated;
grant select, insert, update, delete on table public.stripe_events to service_role;

-- Paid while the subscription is active, the period has not ended, and a
-- failed charge is still inside the 24 hour grace window.
create or replace function public.is_paid(p_profile uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.subscriptions s
    where s.profile_id = p_profile
      and s.status = 'active'
      and s.current_period_end > now()
      and (
        s.payment_failed_at is null
        or s.payment_failed_at > now() - interval '24 hours'
      )
  );
$$;

create or replace function public.stripe_unix(raw text)
returns timestamptz
language sql
immutable
as $$
  select case
    when raw is null or raw = '' or raw !~ '^[0-9]+$' then null
    else to_timestamp(raw::bigint)
  end;
$$;

create or replace function public.stripe_plan_name(p_price text)
returns text
language sql
immutable
as $$
  select case p_price
    when 'price_1UMuSQHcbGkfjKgmtUM0PxPv' then 'monthly'
    when 'price_1UMuSWHcbGkfjKgmMveP00K0' then 'annual'
    else null
  end;
$$;

create or replace function public.stripe_price_cents(p_price text)
returns integer
language sql
immutable
as $$
  select case p_price
    when 'price_1UMuSQHcbGkfjKgmtUM0PxPv' then 4900
    when 'price_1UMuSWHcbGkfjKgmMveP00K0' then 35280
    when 'price_1UMuSXHcbGkfjKgmGdpD1xxa' then 100
    else null
  end;
$$;

create or replace function public.stripe_money(cents integer)
returns text
language sql
immutable
as $$
  select case
    when cents is null then null
    when cents % 100 = 0 then '$' || (cents / 100)::text
    else '$' || to_char(cents / 100.0, 'FM999990.00')
  end;
$$;

-- Hourly. Also safe to call directly: unpaid failures older than 24 hours
-- stop being an active plan.
create or replace function public.downgrade_lapsed_payments()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  update public.subscriptions
  set status = 'unpaid'
  where status = 'active'
    and payment_failed_at is not null
    and payment_failed_at <= now() - interval '24 hours';
  get diagnostics n = row_count;
  return n;
end;
$$;

create or replace function public.apply_stripe_event(p_event jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  kind text := p_event->>'type';
  obj jsonb := p_event #> '{data,object}';
  uid uuid;
  ref text;
  customer text;
  sub_id text;
  price text;
  period timestamptz;
  cents integer;
  failed_at timestamptz;
  stored_status text;
  invoice_id text;
  session_id text;
  receipt text;
  pay_status text;
  descr text;
begin
  if p_event->>'id' is not null then
    insert into public.stripe_events (id) values (p_event->>'id')
    on conflict do nothing;
    if not found then
      return;
    end if;
  end if;

  if obj is null then
    return;
  end if;

  if kind = 'customer.subscription.deleted' then
    obj := jsonb_set(obj, '{status}', '"canceled"'::jsonb);
    kind := 'customer.subscription.updated';
  end if;

  if kind = 'checkout.session.completed' then
    ref := obj->>'client_reference_id';
    begin
      uid := ref::uuid;
    exception when invalid_text_representation then
      return;
    end;
    if uid is null or not exists (select 1 from public.profiles where id = uid) then
      return;
    end if;

    if coalesce(obj->>'mode', '') = 'payment' then
      if obj->>'payment_status' is distinct from 'paid' then
        return;
      end if;
      session_id := obj->>'id';
      cents := coalesce((obj->>'amount_total')::integer, 100);
      descr := case when cents = 100 then '$1 test' else 'Payment' end;
      update public.payments
      set amount = cents,
          currency = coalesce(obj->>'currency', 'usd'),
          status = 'paid',
          description = descr,
          receipt_url = coalesce(obj->>'receipt_url', receipt_url)
      where stripe_checkout_session_id = session_id;
      if not found then
        insert into public.payments (
          profile_id, stripe_checkout_session_id, amount, currency, status, description, receipt_url
        ) values (
          uid, session_id, cents, coalesce(obj->>'currency', 'usd'), 'paid', descr, obj->>'receipt_url'
        );
      end if;
      return;
    end if;

    customer := obj->>'customer';
    sub_id := obj->>'subscription';
    insert into public.subscriptions (
      profile_id, plan, status, current_period_end, stripe_customer_id, stripe_subscription_id
    ) values (
      uid, 'paid', 'active', now() + interval '1 month', customer, nullif(sub_id, '')
    )
    on conflict (profile_id) do update
      set stripe_customer_id = coalesce(excluded.stripe_customer_id, public.subscriptions.stripe_customer_id),
          stripe_subscription_id = coalesce(excluded.stripe_subscription_id, public.subscriptions.stripe_subscription_id),
          status = case
            when public.subscriptions.status = 'unpaid' then public.subscriptions.status
            else 'active'
          end;
    return;
  end if;

  if kind in ('customer.subscription.created', 'customer.subscription.updated') then
    customer := obj->>'customer';
    sub_id := obj->>'id';
    select s.profile_id, s.payment_failed_at
      into uid, failed_at
    from public.subscriptions s
    where (sub_id is not null and s.stripe_subscription_id = sub_id)
       or (customer is not null and s.stripe_customer_id = customer)
    limit 1;
    if uid is null then
      raise exception 'stripe customer is not linked to a user yet';
    end if;

    price := coalesce(
      obj #>> '{items,data,0,price,id}',
      case when jsonb_typeof(obj #> '{items,data,0,price}') = 'string' then obj #>> '{items,data,0,price}' end,
      obj #>> '{items,data,0,plan,id}'
    );
    period := coalesce(
      public.stripe_unix(obj->>'current_period_end'),
      public.stripe_unix(obj #>> '{items,data,0,current_period_end}')
    );
    stored_status := coalesce(obj->>'status', 'active');
    if stored_status in ('past_due', 'unpaid') then
      failed_at := coalesce(failed_at, now());
      if failed_at > now() - interval '24 hours' then
        stored_status := 'active';
      else
        stored_status := 'unpaid';
      end if;
    elsif stored_status = 'active' then
      failed_at := failed_at;
    else
      failed_at := failed_at;
    end if;

    update public.subscriptions
    set stripe_customer_id = coalesce(customer, stripe_customer_id),
        stripe_subscription_id = coalesce(sub_id, stripe_subscription_id),
        price_id = coalesce(price, price_id),
        plan = coalesce(public.stripe_plan_name(price), plan),
        status = stored_status,
        current_period_end = coalesce(period, current_period_end),
        payment_failed_at = case
          when obj->>'status' in ('past_due', 'unpaid') then failed_at
          else payment_failed_at
        end
    where profile_id = uid;
    return;
  end if;

  if kind in ('invoice.paid', 'invoice.payment_failed') then
    customer := obj->>'customer';
    sub_id := obj->>'subscription';
    select s.profile_id into uid
    from public.subscriptions s
    where (sub_id is not null and s.stripe_subscription_id = sub_id)
       or (customer is not null and s.stripe_customer_id = customer)
    limit 1;
    if uid is null then
      raise exception 'stripe customer is not linked to a user yet';
    end if;

    price := coalesce(
      obj #>> '{lines,data,0,price,id}',
      obj #>> '{lines,data,0,pricing,price_details,price}',
      obj #>> '{lines,data,0,plan,id}'
    );
    period := coalesce(
      public.stripe_unix(obj #>> '{lines,data,0,period,end}'),
      public.stripe_unix(obj->>'period_end')
    );
    invoice_id := obj->>'id';
    receipt := coalesce(obj->>'hosted_invoice_url', obj->>'invoice_pdf');
    cents := coalesce(
      case when kind = 'invoice.paid' then (obj->>'amount_paid')::integer else (obj->>'amount_due')::integer end,
      public.stripe_price_cents(price),
      0
    );
    pay_status := case when kind = 'invoice.paid' then 'paid' else 'failed' end;
    descr := case public.stripe_plan_name(coalesce(price, (select price_id from public.subscriptions where profile_id = uid)))
      when 'monthly' then 'Monthly plan'
      when 'annual' then 'Annual plan'
      else 'Subscription'
    end;

    if kind = 'invoice.paid' then
      update public.subscriptions
      set status = 'active',
          payment_failed_at = null,
          price_id = coalesce(price, price_id),
          plan = coalesce(public.stripe_plan_name(price), plan),
          current_period_end = coalesce(period, current_period_end),
          stripe_customer_id = coalesce(customer, stripe_customer_id),
          stripe_subscription_id = coalesce(nullif(sub_id, ''), stripe_subscription_id)
      where profile_id = uid;
    else
      update public.subscriptions
      set payment_failed_at = coalesce(payment_failed_at, now()),
          status = case
            when coalesce(payment_failed_at, now()) > now() - interval '24 hours' then 'active'
            else 'unpaid'
          end
      where profile_id = uid;
    end if;

    if invoice_id is not null then
      update public.payments
      set amount = cents,
          currency = coalesce(obj->>'currency', 'usd'),
          status = pay_status,
          description = descr,
          receipt_url = coalesce(receipt, receipt_url)
      where stripe_invoice_id = invoice_id;
      if not found then
        insert into public.payments (
          profile_id, stripe_invoice_id, amount, currency, status, description, receipt_url,
          created_at
        ) values (
          uid, invoice_id, cents, coalesce(obj->>'currency', 'usd'), pay_status, descr, receipt,
          coalesce(public.stripe_unix(obj->>'created'), now())
        );
      end if;
    end if;
    return;
  end if;
end;
$$;

revoke all on function public.is_paid(uuid) from public;
revoke all on function public.stripe_unix(text) from public;
revoke all on function public.stripe_plan_name(text) from public;
revoke all on function public.stripe_price_cents(text) from public;
revoke all on function public.stripe_money(integer) from public;
revoke all on function public.downgrade_lapsed_payments() from public;
revoke all on function public.apply_stripe_event(jsonb) from public;

grant execute on function public.is_paid(uuid) to authenticated, service_role;
grant execute on function public.downgrade_lapsed_payments() to service_role;
grant execute on function public.apply_stripe_event(jsonb) to service_role;

create or replace function public.my_billing()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  sub public.subscriptions%rowtype;
  cents integer;
  plan_label text;
  price_label text;
  next_label text;
  history jsonb;
  paid boolean;
begin
  paid := public.is_paid(uid);
  if uid is not null then
    select * into sub from public.subscriptions s where s.profile_id = uid;
  end if;
  cents := public.stripe_price_cents(sub.price_id);

  plan_label := case
    when sub.profile_id is not null and sub.plan = 'monthly' and (paid or sub.payment_failed_at is not null) then 'Monthly'
    when sub.profile_id is not null and sub.plan = 'annual' and (paid or sub.payment_failed_at is not null) then 'Annual'
    when paid then 'Paid'
    else 'Free'
  end;

  price_label := case
    when plan_label = 'Monthly' then '$49/month'
    when plan_label = 'Annual' then '$352.80/year'
    when paid then 'Your paid plan is active.'
    else null
  end;

  if sub.current_period_end is not null and cents is not null
     and (paid or sub.payment_failed_at is not null) then
    next_label := to_char(sub.current_period_end, 'Mon FMDD, YYYY')
      || ' · ' || public.stripe_money(cents);
  end if;

  select coalesce(jsonb_agg(row_to_json(p)::jsonb order by p.created_at desc), '[]'::jsonb)
  into history
  from (
    select
      to_char(created_at, 'Mon FMDD, YYYY') as date,
      description,
      amount as amount_cents,
      case when status = 'failed' then 'failed' else 'paid' end as status,
      receipt_url,
      created_at
    from public.payments
    where profile_id = uid
    order by created_at desc
  ) p;

  return jsonb_build_object(
    'tier', public.access_tier(),
    'plan', plan_label,
    'price_label', price_label,
    'next_charge_label', next_label,
    'card', null,
    'payments', coalesce(history, '[]'::jsonb),
    'payment_failed', sub.payment_failed_at is not null,
    'manage_card', sub.stripe_customer_id is not null
  );
end;
$$;

revoke all on function public.my_billing() from public;
grant execute on function public.my_billing() to authenticated, service_role;

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  delete from public.review_ratings
  where review_id in (select id from public.reviews where profile_id = uid);

  delete from public.reviews where profile_id = uid;
  delete from public.watchlist where profile_id = uid;
  delete from public.fund_alert_settings where profile_id = uid;
  delete from public.alert_preferences where profile_id = uid;
  delete from public.report_views where profile_id = uid;
  delete from public.payments where profile_id = uid;
  delete from public.subscriptions where profile_id = uid;
  delete from public.profiles where id = uid;
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

-- Hourly downgrade. Skipped where pg_cron is not installed (local tests).
do $cron$
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    raise notice 'pg_cron is not available; the hourly downgrade is not scheduled';
    return;
  end if;
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron was not created: %', sqlerrm;
    return;
  end;
  begin
    perform cron.unschedule(j.jobid)
    from cron.job j
    where j.jobname = 'downgrade-lapsed-payments';
  exception when others then
    null;
  end;
  perform cron.schedule(
    'downgrade-lapsed-payments',
    '0 * * * *',
    'select public.downgrade_lapsed_payments()'
  );
end
$cron$;
