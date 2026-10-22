-- Regretamin launch: Account + My checks pages, party-only case counts, Stripe-safe account deletion.
-- Per-check date: check_events.created_at of the user's first spend_* event per firm (no new column needed).
-- Save star: existing public.watchlist via watch_fund / unwatch_fund / my_watch_slugs (profiles row comes from handle_new_user).

-- Case facts per check row, shared by firm_case_outline() and my_checks(). party = false when the text says the
-- firm is not a party (e.g. a partner sued as a director, or a non-party subpoena); those get no status and no count.
create or replace function public._firm_cases(p_firm uuid) returns table(rn int, ord bigint, kind text, yr text, status text, is_case boolean, party boolean)
language sql stable security definer set search_path = public as $$
  with r as (select (e->>'row')::int rn, e->'facts' facts from json_array_elements(public.firm_details(p_firm)) e),
  x as (
    select rn, ord, t, c, who, coalesce(y, substring(t from 'filed ((?:19|20)\d\d)')) yr,
      (c is not null or t ~* ' v\.? .*\|.*\y(filed|terminated)\y') is_case,
      t !~* '\ynon-party\y|\ynot a party\y' party
    from r, json_array_elements(r.facts) with ordinality as j(f, ord),
      lateral (select coalesce(f->>'text','') t, f->>'case' c, f->>'who' who, f->>'year' y) v
  )
  select rn, ord,
    case
      when is_case and not party then 'Non-party mention'
      when is_case and t ~* '\y(investigat\w*|probe)\y' then 'Government probe'
      when is_case and t ~* 'class action' then 'Class action'
      when is_case and (who like 'partner:%' or t ~* '\yas an? [a-z]+ director\y|\yrole as\y') then 'Suit naming a partner'
      when is_case and t ~* '\y(plaintiff|backed|joined a suit)\y' then 'Suit brought or backed by the firm'
      when is_case then 'Court case'
      when rn = 10 and t ~* '\yPEP\y' then 'Political-role match'
      when rn = 10 then 'Political-role screen'
      when rn = 8 then 'Registry record'
      when t ~* 'Form ADV|disclosure' then 'Regulator filing'
      when rn = 7 then 'Case-law search'
      else 'List screening'
    end,
    yr,
    case when not is_case or not party then null
      when t ~* '\y(active|pending|ongoing)\y|\yopen\y[,.;:]|\yis investigating\y' then 'active'
      when t ~* '\youtcome (unverified|not verified)\y' then null
      when t ~* '\y(terminated|dismissed|ended in|settled|resolved|closed|affirmed)\y' then 'closed'
    end,
    is_case, party
  from x
$$;
revoke all on function public._firm_cases(uuid) from public, anon, authenticated;

-- Same contract as before (row, kind, year, status only); now built on _firm_cases.
create or replace function public.firm_case_outline(p_slug text) returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('row', rn, 'items', items) order by rn), '[]'::json) from (
    select c.rn, json_agg(json_build_object('kind', c.kind, 'year', c.yr, 'status', c.status)
      order by (c.status = 'active') desc nulls last, c.ord) items
    from firms f, public._firm_cases(f.id) c
    where f.slug = p_slug and f.deleted_at is null and f.published
    group by c.rn) g
$$;
revoke all on function public.firm_case_outline(text) from public;
grant execute on function public.firm_case_outline(text) to anon, authenticated;

-- Account page: plan, checks left, renewal date, whether a Stripe customer exists.
create or replace function public.my_account() returns json
language plpgsql security definer set search_path = public as $$
declare b public.check_balances;
begin
  if auth.uid() is null then return null; end if;
  b := _balance(null);
  return json_build_object('plan', b.plan, 'left', b.free_left + b.paid_left, 'paid_left', b.paid_left,
    'period_end', b.period_end, 'has_customer', b.stripe_customer_id is not null
      or exists (select 1 from subscriptions s where s.profile_id = auth.uid() and s.stripe_customer_id is not null));
end $$;
revoke all on function public.my_account() from public, anon;
grant execute on function public.my_account() to authenticated;

-- My checks: every firm this user spent a check on, newest first, with party-only case counts and save state.
-- Row 9 (cases naming a partner personally) is left out: the firm is not a party there.
create or replace function public.my_checks() returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('slug', f.slug, 'name', f.name, 'short_name', f.short_name,
    'checked_at', e.at, 'active', c.active, 'cases', c.cases,
    'saved', exists (select 1 from watchlist w where w.profile_id = auth.uid() and w.firm_id = f.id)) order by e.at desc), '[]'::json)
  from (select ce.firm_id, min(ce.created_at) at from check_events ce join check_balances b on b.id = ce.balance_id
        where b.user_id = auth.uid() and ce.kind like 'spend_%' and ce.firm_id is not null group by ce.firm_id) e
  join firms f on f.id = e.firm_id
  cross join lateral (select count(*) filter (where status = 'active') active, count(*) filter (where status is not null) cases
                      from public._firm_cases(f.id) where is_case and party and rn <> 9) c
  where auth.uid() is not null
$$;
revoke all on function public.my_checks() from public, anon;
grant execute on function public.my_checks() to authenticated;

-- delete_my_account: also refuse while check_balances still holds a Stripe subscription (the delete-account
-- function cancels it in Stripe and clears it first), and forget launch Stripe customers too.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not authenticated' using errcode = '42501'; end if;
  if exists (select 1 from public.subscriptions s where s.profile_id = uid and s.stripe_subscription_id is not null
               and s.status not in ('canceled', 'incomplete_expired'))
     or exists (select 1 from public.check_balances b where b.user_id = uid and b.stripe_subscription_id is not null) then
    raise exception 'We couldn''t cancel your plan, contact malytskyyo@gmail.com';
  end if;
  insert into public.stripe_forgotten_customers (stripe_customer_id)
  select distinct c from (
    select s.stripe_customer_id c from public.subscriptions s where s.profile_id = uid
    union select b.stripe_customer_id from public.check_balances b where b.user_id = uid) x
  where c is not null
  on conflict do nothing;
  delete from public.review_ratings where review_id in (select id from public.reviews where profile_id = uid);
  delete from public.reviews where profile_id = uid;
  delete from public.watchlist where profile_id = uid;
  delete from public.fund_alert_settings where profile_id = uid;
  delete from public.alert_preferences where profile_id = uid;
  delete from public.report_views where profile_id = uid;
  delete from public.payments where profile_id = uid;
  delete from public.subscriptions where profile_id = uid;
  delete from public.profiles where id = uid;
  delete from auth.users where id = uid; -- check_balances / check_events cascade
end $$;
