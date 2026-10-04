-- The guard fires when alerts turn on, not when an already-on row is edited.
create or replace function public.enforce_fund_alert()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  turning_on boolean;
begin
  -- Each branch is its own statement. A CASE would look up new.enabled
  -- even on the watchlist table, which has no enabled column.
  if tg_table_name = 'watchlist' then
    if tg_op = 'INSERT' then
      turning_on := new.alerts;
    else
      turning_on := new.alerts and not coalesce(old.alerts, false);
    end if;
  elsif tg_op = 'INSERT' then
    turning_on := new.enabled;
  else
    turning_on := new.enabled and not coalesce(old.enabled, false);
  end if;
  if turning_on and not public.can_alert_fund(new.profile_id, new.firm_id) and not public.is_admin() then
    raise exception 'open this report to get alerts' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

-- Per-fund alert kinds live on fund_alert_settings. A watchlist row
-- can turn on New legal matter and Score change separately. Removing the
-- watchlist row still deletes those settings.

alter table public.fund_alert_settings
  add column if not exists new_legal_matter boolean not null default false,
  add column if not exists score_change boolean not null default false;

update public.fund_alert_settings
set new_legal_matter = true,
    score_change = true
where enabled
  and not new_legal_matter
  and not score_change;

create or replace function public.set_fund_alert(p_slug text, p_on boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  fid uuid;
  n integer;
begin
  if uid is null then
    return jsonb_build_object('needAuth', true);
  end if;
  if p_slug is null or p_slug !~ '^[a-z0-9-]{1,80}$' then
    return jsonb_build_object('ok', false, 'reason', 'missing');
  end if;
  select id into fid
  from public.firms
  where slug = p_slug and published and not is_test;
  if fid is null then
    return jsonb_build_object('ok', false, 'reason', 'missing');
  end if;

  if coalesce(p_on, false) then
    if not public.can_alert_fund(uid, fid) then
      return jsonb_build_object('ok', false, 'reason', 'unopened');
    end if;
    if not exists (
      select 1 from public.watchlist where profile_id = uid and firm_id = fid
    ) then
      select count(*) into n from public.watchlist where profile_id = uid;
      if n >= 100 then
        return jsonb_build_object('full', true);
      end if;
    end if;
    insert into public.watchlist (profile_id, firm_id, alerts)
    values (uid, fid, true)
    on conflict (profile_id, firm_id) do update set alerts = true;
    insert into public.fund_alert_settings (
      profile_id, firm_id, enabled, new_legal_matter, score_change
    )
    values (uid, fid, true, true, true)
    on conflict (profile_id, firm_id) do update
      set enabled = true,
          new_legal_matter = true,
          score_change = true,
          updated_at = now();
    return jsonb_build_object('ok', true, 'on', true);
  end if;

  delete from public.fund_alert_settings
  where profile_id = uid and firm_id = fid;
  update public.watchlist
  set alerts = false
  where profile_id = uid and firm_id = fid;
  return jsonb_build_object('ok', true, 'on', false);
exception
  when check_violation then
    if sqlerrm ilike '%watchlist full%' then
      return jsonb_build_object('full', true);
    end if;
    return jsonb_build_object('ok', false, 'reason', 'unopened');
end;
$$;

create or replace function public.set_fund_alert_kind(
  p_slug text,
  p_kind text,
  p_on boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  fid uuid;
  legal boolean;
  score boolean;
begin
  if uid is null then
    return jsonb_build_object('needAuth', true);
  end if;
  if p_slug is null or p_slug !~ '^[a-z0-9-]{1,80}$' then
    return jsonb_build_object('ok', false, 'reason', 'missing');
  end if;
  if p_kind not in ('new_legal_matter', 'score_change') then
    return jsonb_build_object('ok', false, 'reason', 'missing');
  end if;
  select id into fid
  from public.firms
  where slug = p_slug and published and not is_test;
  if fid is null then
    return jsonb_build_object('ok', false, 'reason', 'missing');
  end if;
  if not exists (
    select 1 from public.watchlist where profile_id = uid and firm_id = fid
  ) then
    return jsonb_build_object('ok', false, 'reason', 'missing');
  end if;

  if coalesce(p_on, false) and not public.can_alert_fund(uid, fid) then
    return jsonb_build_object('ok', false, 'reason', 'unopened');
  end if;

  insert into public.fund_alert_settings (
    profile_id, firm_id, enabled, new_legal_matter, score_change
  )
  values (
    uid,
    fid,
    coalesce(p_on, false),
    p_kind = 'new_legal_matter' and coalesce(p_on, false),
    p_kind = 'score_change' and coalesce(p_on, false)
  )
  on conflict (profile_id, firm_id) do update
    set new_legal_matter = case
          when p_kind = 'new_legal_matter' then coalesce(p_on, false)
          else public.fund_alert_settings.new_legal_matter
        end,
        score_change = case
          when p_kind = 'score_change' then coalesce(p_on, false)
          else public.fund_alert_settings.score_change
        end,
        updated_at = now();

  update public.fund_alert_settings
  set enabled = new_legal_matter or score_change
  where profile_id = uid and firm_id = fid
  returning new_legal_matter, score_change into legal, score;

  update public.watchlist
  set alerts = legal or score
  where profile_id = uid and firm_id = fid;

  return jsonb_build_object(
    'ok', true,
    'new_legal_matter', legal,
    'score_change', score
  );
exception
  when check_violation then
    return jsonb_build_object('ok', false, 'reason', 'unopened');
end;
$$;

create or replace function public.my_alert_funds()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(item order by item->>'name'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'slug', f.slug,
      'name', f.name,
      'alerts', coalesce(w.alerts, false) or coalesce(s.enabled, false),
      'new_legal_matter', coalesce(s.new_legal_matter, false),
      'score_change', coalesce(s.score_change, false),
      'opened', exists (
        select 1 from public.report_views v
        where v.profile_id = auth.uid() and v.firm_id = f.id
      )
    ) as item
    from public.firms f
    left join public.watchlist w
      on w.firm_id = f.id and w.profile_id = auth.uid()
    left join public.fund_alert_settings s
      on s.firm_id = f.id and s.profile_id = auth.uid()
    where auth.uid() is not null
      and f.published
      and not f.is_test
      and (
        w.profile_id is not null
        or s.profile_id is not null
        or exists (
          select 1 from public.report_views v
          where v.profile_id = auth.uid() and v.firm_id = f.id
        )
      )
  ) rows;
$$;

revoke all on function public.set_fund_alert_kind(text, text, boolean) from public;
grant execute on function public.set_fund_alert_kind(text, text, boolean) to authenticated, service_role;

-- After the 24 hour grace window the plan is Free and the failure date
-- is the charge line. Inside the window the plan stays paid.
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
