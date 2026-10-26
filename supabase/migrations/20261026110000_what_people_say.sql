-- "What people say" (firm-page Activity reviews block): every public, approved review shows, not only founder
-- ones, and each item carries its stored type so the page can show a type pill. company reviews show as
-- 'portfolio' only when our investments data says this firm backed that company. Founder reviews stay first.
-- Additive: no rows change, nothing is dropped.

create index if not exists reviews_firm_public_idx on public.reviews (firm_id, reviewed_on desc nulls last) where is_public and moderation_status = 'approved';

create or replace function public._activity_review(r public.reviews, c public.portfolio_companies)
returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object(
    'author', case when coalesce(r.anonymous, false) then null else nullif(btrim(r.author_name), '') end,
    'role', r.role_label, 'round', r.round_label, 'company', c.name,
    'date', r.reviewed_on, 'date_precision', r.date_precision,
    'body', r.body, 'verified', r.verification_status = 'verified',
    'type', case when r.review_type = 'company' and c.id is not null and exists (select 1 from investments i
                  where i.firm_id = r.firm_id and i.company_id = c.id and i.data_status = 'real') then 'portfolio'
                 else coalesce(r.review_type, 'founder') end,
    'ratings', jsonb_strip_nulls(jsonb_build_object('honesty', r.honesty, 'support_after_check', r.support_after_check,
      'founder_friendly_terms', r.founder_friendly_terms, 'responsiveness', r.responsiveness, 'hard_times', r.hard_times)),
    'url', (select u from unnest(coalesce(r.source_urls, '{}')) u where u ~* '^https?://' limit 1));
$$;
revoke all on function public._activity_review(public.reviews, public.portfolio_companies) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public._firm_activity(p_firm uuid, p_open boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  since date := current_date - 365;
  d0 jsonb; r0 jsonb; fund jsonb;
  n_deals int; n_deals12 int; n_revs int; n_close12 int;
begin
  select count(*), count(*) filter (where i.invested_on >= since) into n_deals, n_deals12
    from investments i where i.firm_id = p_firm and i.data_status = 'real';
  select _activity_deal(i, c) into d0
    from investments i left join portfolio_companies c on c.id = i.company_id
   where i.firm_id = p_firm and i.data_status = 'real'
   order by i.invested_on desc nulls last, c.name limit 1;

  select count(*) into n_revs from reviews r
   where r.firm_id = p_firm and r.is_public and r.moderation_status = 'approved';
  select _activity_review(r, c) into r0
    from reviews r left join portfolio_companies c on c.id = r.company_id
   where r.firm_id = p_firm and r.is_public and r.moderation_status = 'approved'
   order by (r.review_type = 'founder') desc, r.reviewed_on desc nulls last, r.created_at desc limit 1;

  select count(*) into n_close12 from funds
   where firm_id = p_firm and data_status = 'real' and closed_on >= since;

  select jsonb_build_object('name', x.name, 'raised_usd', coalesce(x.raised_usd, x.size_usd), 'target_usd', x.target_usd,
           'status', x.close_status, 'date', x.closed_on, 'date_precision', x.date_precision, 'vintage', x.vintage,
           'url', coalesce(nullif(x.filing_url, ''), (select u from unnest(coalesce(x.source_urls, '{}')) u where u ~* '^https?://' limit 1)))
    into fund
    from funds x
   where x.firm_id = p_firm and x.data_status = 'real'
   order by x.closed_on desc nulls last, x.vintage desc nulls last, x.created_at desc
   limit 1;

  -- deals / reviews: first slice only (the full lists come from firm_activity_list when "Show all" opens)
  return jsonb_build_object(
    'active', n_deals12 > 0 or n_close12 > 0,
    'deals_12m', n_deals12,
    'funds_closed_12m', n_close12,
    'latest_fund', fund,
    'latest_deal', d0,
    'latest_review', r0,
    'counts', jsonb_build_object('deals', n_deals, 'reviews', n_revs),
    'deals', case when p_open then case when d0 is null then '[]'::jsonb else jsonb_build_array(d0) end end,
    'reviews', case when p_open then case when r0 is null then '[]'::jsonb else jsonb_build_array(r0) end end,
    'lazy', true);
end $function$;

CREATE OR REPLACE FUNCTION public.firm_activity_list(p_slug text, p_anon uuid, p_kind text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b public.check_balances; f uuid; out jsonb;
begin
  if p_anon is null then return json_build_object('status', 'locked'); end if;
  select id into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f is null then return json_build_object('status', 'not_found'); end if;
  b := _balance(p_anon);
  if coalesce((select sum(case when kind like 'spend_%' then 1 when kind = 'refund_ondemand' then -1 else 0 end) from check_events
               where balance_id = b.id and firm_id = f), 0) <= 0 then
    return json_build_object('status', 'locked');
  end if;
  if p_kind = 'deals' then
    select coalesce(jsonb_agg(_activity_deal(i, c) order by i.invested_on desc nulls last, c.name), '[]') into out
      from investments i left join portfolio_companies c on c.id = i.company_id
     where i.firm_id = f and i.data_status = 'real';
  elsif p_kind = 'revs' then
    select coalesce(jsonb_agg(_activity_review(r, c) order by (r.review_type = 'founder') desc, r.reviewed_on desc nulls last, r.created_at desc), '[]') into out
      from reviews r left join portfolio_companies c on c.id = r.company_id
     where r.firm_id = f and r.is_public and r.moderation_status = 'approved';
  else
    return json_build_object('status', 'bad_kind');
  end if;
  return json_build_object('status', 'ok', 'items', out);
end $function$;

revoke all on function public.firm_activity_list(text, uuid, text) from public;
grant execute on function public.firm_activity_list(text, uuid, text) to anon, authenticated;
