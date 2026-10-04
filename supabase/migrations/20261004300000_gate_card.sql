-- Closed-gate score card, and the card brand plus last 4 on the subscription.

alter table public.subscriptions
  add column if not exists card_brand text,
  add column if not exists card_last4 text;

create or replace function public.stripe_card_label(p_brand text, p_last4 text)
returns text
language sql
immutable
as $$
  select case
    when p_last4 is null or p_last4 !~ '^[0-9]{4}$' then null
    else initcap(coalesce(nullif(btrim(p_brand), ''), 'Card')) || ' •••• ' || p_last4
  end;
$$;

create or replace function public.stripe_note_card(p_obj jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  brand text;
  last4 text;
  customer text;
  sub_id text;
begin
  if p_obj is null or jsonb_typeof(p_obj) <> 'object' then
    return;
  end if;
  brand := coalesce(
    p_obj #>> '{payment_method_details,card,brand}',
    p_obj #>> '{charge,payment_method_details,card,brand}',
    p_obj #>> '{charges,data,0,payment_method_details,card,brand}',
    p_obj #>> '{payment_intent,charges,data,0,payment_method_details,card,brand}',
    p_obj #>> '{latest_charge,payment_method_details,card,brand}'
  );
  last4 := coalesce(
    p_obj #>> '{payment_method_details,card,last4}',
    p_obj #>> '{charge,payment_method_details,card,last4}',
    p_obj #>> '{charges,data,0,payment_method_details,card,last4}',
    p_obj #>> '{payment_intent,charges,data,0,payment_method_details,card,last4}',
    p_obj #>> '{latest_charge,payment_method_details,card,last4}'
  );
  if last4 is null or last4 !~ '^[0-9]{4}$' then
    return;
  end if;
  customer := nullif(p_obj->>'customer', '');
  sub_id := nullif(p_obj->>'subscription', '');
  if customer is not null and exists (
    select 1 from public.stripe_forgotten_customers f where f.stripe_customer_id = customer
  ) then
    return;
  end if;
  update public.subscriptions
  set card_brand = coalesce(nullif(btrim(brand), ''), card_brand),
      card_last4 = last4
  where (customer is not null and stripe_customer_id = customer)
     or (sub_id is not null and stripe_subscription_id = sub_id);
end;
$$;

revoke all on function public.stripe_note_card(jsonb) from public;
grant execute on function public.stripe_note_card(jsonb) to service_role;

create or replace function public.open_report(p_slug text, p_anon_key text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  fid uuid;
  v_tier text := public.access_tier();
  v_html text;
  v_cap integer;
  v_anon integer;
  v_extra integer;
  v_used integer;
  v_existing uuid;
  v_summary jsonb;
begin
  if p_slug is null or p_slug !~ '^[a-z0-9-]{1,80}$' then
    return jsonb_build_object('ok', false, 'reason', 'missing');
  end if;

  select id into fid
  from public.firms
  where slug = p_slug and published and not is_test;
  if fid is null then
    return jsonb_build_object('ok', false, 'reason', 'missing');
  end if;

  select jsonb_build_object(
    'name', f.name,
    'short', f.short_name,
    'score', f.list_score,
    'band', f.list_band,
    'lo', f.list_range_low,
    'hi', f.list_range_high
  ) into v_summary
  from public.firms f
  where f.id = fid;

  select html into v_html from public.report_pages where slug = p_slug;

  if v_html is null or v_html = '' then
    select b.payload->>'html' into v_html
    from public.report_bundles b
    where b.firm_id = fid;
  end if;

  if v_html is null then
    return jsonb_build_object('ok', false, 'reason', 'unpublished', 'tier', v_tier);
  end if;

  if uid is null and (p_anon_key is null or p_anon_key !~ '^[A-Za-z0-9_-]{8,80}$') then
    return jsonb_build_object('ok', false, 'reason', 'anon', 'tier', v_tier);
  end if;

  perform pg_advisory_xact_lock(hashtext(coalesce(uid::text, 'anon:' || p_anon_key)));

  if uid is null then
    select id into v_existing
    from public.report_views
    where anon_key = p_anon_key and firm_id = fid;
  else
    select id into v_existing
    from public.report_views
    where profile_id = uid and firm_id = fid;
  end if;

  if v_existing is not null then
    update public.report_views
    set last_opened_at = now(), counted = true
    where id = v_existing;
    return jsonb_build_object(
      'ok', true,
      'html', v_html,
      'repeat', true,
      'tier', v_tier
    );
  end if;

  select anonymous_free_reports, registered_extra_reports
  into v_anon, v_extra
  from public.gating_policies
  where code = 'default';
  v_anon := coalesce(v_anon, 2);
  v_extra := coalesce(v_extra, 5);
  if v_tier = 'paid' then
    v_cap := null;
  elsif v_tier = 'free' then
    v_cap := v_anon + v_extra;
  else
    v_cap := v_anon;
  end if;

  if uid is null then
    select count(*) into v_used from public.report_views where anon_key = p_anon_key;
  else
    select count(*) into v_used from public.report_views where profile_id = uid;
  end if;

  if v_cap is not null and v_used >= v_cap then
    return jsonb_build_object(
      'ok', false,
      'reason', 'limit',
      'plans', v_tier = 'free',
      'tier', v_tier,
      'used', v_used,
      'cap', v_cap,
      'summary', v_summary
    );
  end if;

  insert into public.report_views (profile_id, anon_key, firm_id, source, dwell_ms, counted)
  values (
    uid,
    case when uid is null then p_anon_key else null end,
    fid,
    'report',
    0,
    true
  );

  return jsonb_build_object(
    'ok', true,
    'html', v_html,
    'repeat', false,
    'tier', v_tier,
    'used', v_used + 1,
    'cap', v_cap
  );
exception
  when unique_violation then
    return jsonb_build_object(
      'ok', true,
      'html', v_html,
      'repeat', true,
      'tier', v_tier
    );
end;
$$;


create or replace function public.apply_stripe_event(p_event jsonb)
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
      perform public.stripe_note_card(obj);
    return '{}'::jsonb;
    end if;
  end if;

  if obj is null then
    perform public.stripe_note_card(obj);
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
    perform public.stripe_note_card(obj);
    return '{}'::jsonb;
  end if;

  if kind = 'checkout.session.completed' then
    ref := obj->>'client_reference_id';
    begin
      uid := ref::uuid;
    exception when invalid_text_representation then
      perform public.stripe_note_card(obj);
    return '{}'::jsonb;
    end;
    if uid is null or not exists (select 1 from public.profiles where id = uid) then
      perform public.stripe_note_card(obj);
    return '{}'::jsonb;
    end if;

    if coalesce(obj->>'mode', '') = 'payment' then
      if obj->>'payment_status' is distinct from 'paid' then
        perform public.stripe_note_card(obj);
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
      perform public.stripe_note_card(obj);
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
      perform public.stripe_note_card(obj);
      return jsonb_build_object('cancel_at_period_end', to_jsonb(older));
    end if;
    perform public.stripe_note_card(obj);
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
        perform public.stripe_note_card(obj);
    return '{}'::jsonb;
      end if;
      if coalesce(obj->>'status', '') = 'canceled' then
        perform public.stripe_note_card(obj);
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
      perform public.stripe_note_card(obj);
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
    perform public.stripe_note_card(obj);
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
        perform public.stripe_note_card(obj);
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
    perform public.stripe_note_card(obj);
    return '{}'::jsonb;
  end if;

  perform public.stripe_note_card(obj);
    return '{}'::jsonb;
end;
$$;


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
  failed_on text;
  history jsonb;
  paid boolean;
  lapsed boolean;
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
  lapsed := sub.payment_failed_at is not null and not paid;

  plan_label := case
    when paid and sub.plan = 'monthly' then 'Monthly'
    when paid and sub.plan = 'annual' then 'Annual'
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
     and paid and sub.payment_failed_at is null then
    next_label := to_char(sub.current_period_end, 'Mon FMDD, YYYY')
      || ' · ' || public.stripe_money(cents);
  end if;

  if sub.payment_failed_at is not null then
    failed_on := to_char(sub.payment_failed_at, 'Mon FMDD, YYYY');
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
    'payment_failed_on', failed_on,
    'lapsed', lapsed,
    'card', case
      when sub.card_last4 ~ '^[0-9]{4}$' then jsonb_build_object(
        'brand', initcap(coalesce(nullif(btrim(sub.card_brand), ''), 'Card')),
        'last4', sub.card_last4,
        'label', public.stripe_card_label(sub.card_brand, sub.card_last4)
      )
      else null
    end,
    'payments', coalesce(history, '[]'::jsonb),
    'payment_failed', sub.payment_failed_at is not null,
    'manage_card', exists (
      select 1 from public.subscriptions s
      where s.profile_id = uid and s.stripe_customer_id is not null
    )
  );
end;
$$;
