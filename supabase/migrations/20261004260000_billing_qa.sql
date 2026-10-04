-- Several subscriptions per user, keyed by the Stripe subscription id.
-- A customer can be remembered after the account is deleted so later
-- webhooks are ignored instead of retried.

alter table public.subscriptions drop constraint subscriptions_pkey;
alter table public.subscriptions alter column profile_id drop not null;
alter table public.subscriptions add column id uuid default gen_random_uuid() not null;
alter table public.subscriptions add constraint subscriptions_pkey primary key (id);
alter table public.subscriptions add column flagged boolean not null default false;

comment on column public.subscriptions.flagged is
  'True when this row is a second active subscription for someone who already had one.';

create index subscriptions_profile_idx on public.subscriptions (profile_id);

drop index if exists subscriptions_stripe_customer_uidx;
create index subscriptions_stripe_customer_idx
  on public.subscriptions (stripe_customer_id)
  where stripe_customer_id is not null;

alter table public.payments alter column profile_id drop not null;
alter table public.payments add column stripe_customer_id text;
alter table public.payments add column stripe_subscription_id text;

create table public.stripe_forgotten_customers (
  stripe_customer_id text primary key,
  forgotten_at timestamptz not null default now()
);

alter table public.stripe_forgotten_customers enable row level security;
alter table public.stripe_forgotten_customers force row level security;
revoke all on table public.stripe_forgotten_customers from public, anon, authenticated;
grant select, insert, update, delete on table public.stripe_forgotten_customers to service_role;

comment on table public.stripe_forgotten_customers is
  'Stripe customers whose Regrettamine account was deleted. Webhooks for these customers are ignored.';

-- Manual grants (founder, tests) still update one non-Stripe row per user.
create or replace function public.apply_subscription(
  p_profile_id uuid,
  p_plan text,
  p_status text,
  p_current_period_end timestamptz
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_profile_id is null or p_plan is null or p_status is null or p_current_period_end is null then
    raise exception 'apply_subscription needs a profile, plan, status, and current_period_end';
  end if;
  update public.subscriptions
  set plan = p_plan,
      status = p_status,
      current_period_end = p_current_period_end,
      updated_at = now()
  where profile_id = p_profile_id
    and stripe_subscription_id is null;
  if not found then
    insert into public.subscriptions (profile_id, plan, status, current_period_end)
    values (p_profile_id, p_plan, p_status, p_current_period_end);
  end if;
end;
$$;

drop function if exists public.apply_stripe_event(jsonb);

create function public.apply_stripe_event(p_event jsonb)
returns jsonb
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
  subrow public.subscriptions%rowtype;
  older text[];
begin
  if p_event->>'id' is not null then
    insert into public.stripe_events (id) values (p_event->>'id')
    on conflict do nothing;
    if not found then
      return '{}'::jsonb;
    end if;
  end if;

  if obj is null then
    return '{}'::jsonb;
  end if;

  if kind = 'customer.subscription.deleted' then
    obj := jsonb_set(obj, '{status}', '"canceled"'::jsonb);
    kind := 'customer.subscription.updated';
  end if;

  customer := nullif(obj->>'customer', '');
  if customer is not null and exists (
    select 1 from public.stripe_forgotten_customers f where f.stripe_customer_id = customer
  ) then
    return '{}'::jsonb;
  end if;

  if kind = 'checkout.session.completed' then
    ref := obj->>'client_reference_id';
    begin
      uid := ref::uuid;
    exception when invalid_text_representation then
      return '{}'::jsonb;
    end;
    if uid is null or not exists (select 1 from public.profiles where id = uid) then
      return '{}'::jsonb;
    end if;

    if coalesce(obj->>'mode', '') = 'payment' then
      if obj->>'payment_status' is distinct from 'paid' then
        return '{}'::jsonb;
      end if;
      session_id := obj->>'id';
      cents := coalesce((obj->>'amount_total')::integer, 100);
      descr := case when cents = 100 then '$1 test' else 'Payment' end;
      update public.payments
      set profile_id = uid,
          amount = cents,
          currency = coalesce(obj->>'currency', 'usd'),
          status = 'paid',
          description = descr,
          receipt_url = coalesce(obj->>'receipt_url', receipt_url),
          stripe_customer_id = coalesce(customer, stripe_customer_id)
      where stripe_checkout_session_id = session_id;
      if not found then
        insert into public.payments (
          profile_id, stripe_checkout_session_id, stripe_customer_id,
          amount, currency, status, description, receipt_url
        ) values (
          uid, session_id, customer, cents, coalesce(obj->>'currency', 'usd'),
          'paid', descr, obj->>'receipt_url'
        );
      end if;
      return '{}'::jsonb;
    end if;

    sub_id := nullif(obj->>'subscription', '');
    update public.subscriptions
    set profile_id = uid
    where profile_id is null
      and (
        (customer is not null and stripe_customer_id = customer)
        or (sub_id is not null and stripe_subscription_id = sub_id)
      );
    update public.payments
    set profile_id = uid
    where profile_id is null
      and (
        (customer is not null and stripe_customer_id = customer)
        or (sub_id is not null and stripe_subscription_id = sub_id)
      );

    if sub_id is not null and not exists (
      select 1 from public.subscriptions s where s.stripe_subscription_id = sub_id
    ) then
      insert into public.subscriptions (
        profile_id, plan, status, current_period_end, stripe_customer_id, stripe_subscription_id
      ) values (
        uid, 'paid', 'active', now() + interval '1 month', customer, sub_id
      );
    elsif sub_id is null and customer is not null and not exists (
      select 1 from public.subscriptions s
      where s.profile_id = uid and s.stripe_customer_id = customer
    ) then
      insert into public.subscriptions (
        profile_id, plan, status, current_period_end, stripe_customer_id, stripe_subscription_id
      ) values (
        uid, 'paid', 'active', now() + interval '1 month', customer, null
      );
    end if;

    select coalesce(array_agg(s.stripe_subscription_id order by s.created_at), array[]::text[])
      into older
    from public.subscriptions s
    where s.profile_id = uid
      and s.status = 'active'
      and s.current_period_end > now()
      and s.stripe_subscription_id is not null
      and s.stripe_subscription_id is distinct from sub_id;

    if coalesce(array_length(older, 1), 0) > 0 then
      update public.subscriptions
      set flagged = true
      where profile_id = uid
        and (
          (sub_id is not null and stripe_subscription_id = sub_id)
          or (sub_id is null and customer is not null and stripe_customer_id = customer)
        );
      session_id := obj->>'id';
      cents := coalesce((obj->>'amount_total')::integer, 0);
      if session_id is not null and not exists (
        select 1 from public.payments p where p.stripe_checkout_session_id = session_id
      ) then
        insert into public.payments (
          profile_id, stripe_checkout_session_id, stripe_customer_id, stripe_subscription_id,
          amount, currency, status, description
        ) values (
          uid, session_id, customer, sub_id, cents, coalesce(obj->>'currency', 'usd'),
          'paid', 'Duplicate subscription'
        );
      end if;
      return jsonb_build_object('cancel_at_period_end', to_jsonb(older));
    end if;
    return '{}'::jsonb;
  end if;

  if kind in ('customer.subscription.created', 'customer.subscription.updated') then
    sub_id := nullif(obj->>'id', '');
    price := coalesce(
      obj #>> '{items,data,0,price,id}',
      case when jsonb_typeof(obj #> '{items,data,0,price}') = 'string' then obj #>> '{items,data,0,price}' end,
      obj #>> '{items,data,0,plan,id}'
    );
    period := coalesce(
      public.stripe_unix(obj->>'current_period_end'),
      public.stripe_unix(obj #>> '{items,data,0,current_period_end}')
    );
    if sub_id is not null then
      select * into subrow from public.subscriptions s where s.stripe_subscription_id = sub_id;
    end if;
    if subrow.id is null and customer is not null and sub_id is null then
      select * into subrow
      from public.subscriptions s
      where s.stripe_customer_id = customer
      order by s.created_at desc
      limit 1;
    end if;
    if subrow.id is null and customer is not null and sub_id is not null then
      select * into subrow
      from public.subscriptions s
      where s.stripe_customer_id = customer
        and s.stripe_subscription_id is null
      order by s.created_at desc
      limit 1;
    end if;

    failed_at := subrow.payment_failed_at;
    stored_status := coalesce(obj->>'status', 'active');
    if stored_status in ('past_due', 'unpaid') then
      failed_at := coalesce(failed_at, now());
      if failed_at > now() - interval '24 hours' then
        stored_status := 'active';
      else
        stored_status := 'unpaid';
      end if;
    end if;

    if subrow.id is null then
      if sub_id is null and customer is null then
        return '{}'::jsonb;
      end if;
      if coalesce(obj->>'status', '') = 'canceled' then
        return '{}'::jsonb;
      end if;
      insert into public.subscriptions (
        profile_id, plan, status, current_period_end,
        stripe_customer_id, stripe_subscription_id, price_id, payment_failed_at
      ) values (
        null,
        coalesce(public.stripe_plan_name(price), 'paid'),
        stored_status,
        coalesce(period, now() + interval '1 month'),
        customer,
        sub_id,
        price,
        case when obj->>'status' in ('past_due', 'unpaid') then failed_at else null end
      );
      return '{}'::jsonb;
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
    where id = subrow.id;
    return '{}'::jsonb;
  end if;

  if kind in ('invoice.paid', 'invoice.payment_failed') then
    sub_id := nullif(obj->>'subscription', '');
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

    if sub_id is not null then
      select * into subrow from public.subscriptions s where s.stripe_subscription_id = sub_id;
    end if;
    if subrow.id is null and customer is not null and sub_id is null then
      select * into subrow
      from public.subscriptions s
      where s.stripe_customer_id = customer
      order by s.created_at desc
      limit 1;
    end if;
    if subrow.id is null and customer is not null and sub_id is not null then
      select * into subrow
      from public.subscriptions s
      where s.stripe_customer_id = customer
        and s.stripe_subscription_id is null
      order by s.created_at desc
      limit 1;
    end if;

    if subrow.id is null then
      if sub_id is null and customer is null then
        return '{}'::jsonb;
      end if;
      insert into public.subscriptions (
        profile_id, plan, status, current_period_end,
        stripe_customer_id, stripe_subscription_id, price_id,
        payment_failed_at
      ) values (
        null,
        coalesce(public.stripe_plan_name(price), 'paid'),
        case
          when kind = 'invoice.paid' then 'active'
          else 'active'
        end,
        coalesce(period, now() + interval '1 month'),
        customer,
        sub_id,
        price,
        case when kind = 'invoice.payment_failed' then now() else null end
      );
    else
      if kind = 'invoice.paid' then
        update public.subscriptions
        set status = 'active',
            payment_failed_at = null,
            price_id = coalesce(price, price_id),
            plan = coalesce(public.stripe_plan_name(price), plan),
            current_period_end = coalesce(period, current_period_end),
            stripe_customer_id = coalesce(customer, stripe_customer_id),
            stripe_subscription_id = coalesce(sub_id, stripe_subscription_id)
        where id = subrow.id;
      else
        update public.subscriptions
        set payment_failed_at = coalesce(payment_failed_at, now()),
            status = case
              when coalesce(payment_failed_at, now()) > now() - interval '24 hours' then 'active'
              else 'unpaid'
            end
        where id = subrow.id;
      end if;
    end if;

    descr := case public.stripe_plan_name(price)
      when 'monthly' then 'Monthly plan'
      when 'annual' then 'Annual plan'
      else 'Subscription'
    end;
    if invoice_id is not null then
      update public.payments
      set amount = cents,
          currency = coalesce(obj->>'currency', 'usd'),
          status = pay_status,
          description = descr,
          receipt_url = coalesce(receipt, receipt_url),
          stripe_customer_id = coalesce(customer, stripe_customer_id),
          stripe_subscription_id = coalesce(sub_id, stripe_subscription_id),
          profile_id = coalesce(profile_id, subrow.profile_id)
      where stripe_invoice_id = invoice_id;
      if not found then
        insert into public.payments (
          profile_id, stripe_invoice_id, stripe_customer_id, stripe_subscription_id,
          amount, currency, status, description, receipt_url, created_at
        ) values (
          subrow.profile_id, invoice_id, customer, sub_id,
          cents, coalesce(obj->>'currency', 'usd'), pay_status, descr, receipt,
          coalesce(public.stripe_unix(obj->>'created'), now())
        );
      end if;
    end if;
    return '{}'::jsonb;
  end if;

  return '{}'::jsonb;
end;
$$;

revoke all on function public.apply_stripe_event(jsonb) from public;
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
    select * into sub
    from public.subscriptions s
    where s.profile_id = uid
    order by
      case
        when s.status = 'active' and s.current_period_end > now() and not s.flagged then 0
        when s.status = 'active' and s.current_period_end > now() then 1
        when s.payment_failed_at is not null then 2
        else 3
      end,
      s.current_period_end desc nulls last
    limit 1;
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
    'manage_card', exists (
      select 1 from public.subscriptions s
      where s.profile_id = uid and s.stripe_customer_id is not null
    )
  );
end;
$$;

-- Refuses while a Stripe subscription is still active. The delete-account
-- function cancels those at Stripe, marks them canceled, then calls this.
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

  if exists (
    select 1
    from public.subscriptions s
    where s.profile_id = uid
      and s.stripe_subscription_id is not null
      and s.status not in ('canceled', 'incomplete_expired')
  ) then
    raise exception 'We couldn''t cancel your plan, contact malytskyyo@gmail.com';
  end if;

  insert into public.stripe_forgotten_customers (stripe_customer_id)
  select distinct s.stripe_customer_id
  from public.subscriptions s
  where s.profile_id = uid
    and s.stripe_customer_id is not null
  on conflict do nothing;

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
