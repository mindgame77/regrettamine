-- Step 5 of the activity work: firm_page() gets an additive 'activity' key.
-- Read live from investments, funds and reviews on every call (no cache), so a
-- new or removed row shows on the next page load.
-- Never returns profile_id, linkedin_url or any person id.
-- Locked page: tiles, counts, the latest deal and the latest review.
-- After a credit: the same plus the full deal and review lists.

create or replace function public._activity_deal(i public.investments, c public.portfolio_companies)
returns jsonb language sql immutable set search_path = public as $$
  select jsonb_build_object(
    'company', c.name, 'domain', c.domain, 'round', i.round_name,
    'date', i.invested_on, 'date_precision', i.date_precision,
    'amount', i.amount, 'currency', i.currency, 'lead', i.is_lead,
    'url', (select u from unnest(coalesce(i.source_urls, '{}')) u where u ~* '^https?://' limit 1));
$$;

create or replace function public._activity_review(r public.reviews, c public.portfolio_companies)
returns jsonb language sql immutable set search_path = public as $$
  select jsonb_build_object(
    'author', case when coalesce(r.anonymous, false) then null else nullif(btrim(r.author_name), '') end,
    'role', r.role_label, 'round', r.round_label, 'company', c.name,
    'date', r.reviewed_on, 'date_precision', r.date_precision,
    'body', r.body, 'verified', r.verification_status = 'verified',
    'ratings', jsonb_strip_nulls(jsonb_build_object('honesty', r.honesty, 'support_after_check', r.support_after_check,
      'founder_friendly_terms', r.founder_friendly_terms, 'responsiveness', r.responsiveness, 'hard_times', r.hard_times)),
    'url', (select u from unnest(coalesce(r.source_urls, '{}')) u where u ~* '^https?://' limit 1));
$$;

create or replace function public._firm_activity(p_firm uuid, p_open boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  since date := current_date - 365;
  deals jsonb; revs jsonb; fund jsonb;
  n_deals int; n_deals12 int; n_revs int; n_close12 int;
begin
  select coalesce(jsonb_agg(_activity_deal(i, c) order by i.invested_on desc nulls last, c.name), '[]'), count(*),
         count(*) filter (where i.invested_on >= since)
    into deals, n_deals, n_deals12
    from investments i left join portfolio_companies c on c.id = i.company_id
   where i.firm_id = p_firm and i.data_status = 'real';

  select coalesce(jsonb_agg(_activity_review(r, c) order by r.reviewed_on desc nulls last, r.created_at desc), '[]'), count(*)
    into revs, n_revs
    from reviews r left join portfolio_companies c on c.id = r.company_id
   where r.firm_id = p_firm and r.review_type = 'founder' and r.is_public and r.moderation_status = 'approved';

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

  return jsonb_build_object(
    'active', n_deals12 > 0 or n_close12 > 0,
    'deals_12m', n_deals12,
    'funds_closed_12m', n_close12,
    'latest_fund', fund,
    'latest_deal', deals->0,
    'latest_review', revs->0,
    'counts', jsonb_build_object('deals', n_deals, 'reviews', n_revs),
    'deals', case when p_open then deals end,
    'reviews', case when p_open then revs end);
end $$;

revoke all on function public._firm_activity(uuid, boolean) from public, anon, authenticated;
revoke all on function public._activity_deal(public.investments, public.portfolio_companies) from public, anon, authenticated;
revoke all on function public._activity_review(public.reviews, public.portfolio_companies) from public, anon, authenticated;

-- firm_page: unchanged except the new last key.
CREATE OR REPLACE FUNCTION public.firm_page(p_slug text, p_anon uuid, p_spend boolean DEFAULT false, p_email text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f firms; u json; open boolean; secs jsonb := '[]'; s page_sections; it jsonb; hero jsonb; q research_queue; qid text;
  vq text; vs timestamptz; hq text; web text; assets text;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  u := unlock_firm(p_slug, p_anon, p_spend, p_email);
  open := u->>'status' = 'ok';
  if u->>'status' not in ('ok', 'locked') then return u; end if;
  qid := _firm_queue_id(f.id);
  if qid is not null then select * into q from research_queue where registry_id = qid; end if;
  hq := coalesce(nullif(btrim(f.hq), ''), public.firm_hq_format(q.hq_city, q.state, q.country));
  web := public._firm_website(f.id, f.primary_domain);
  assets := public._firm_assets(f.id);
  if not open then
    select coalesce(jsonb_agg(jsonb_build_object('label', hero_label, 'value', hero_value, 'anchor', section,
        'src', _src('firm_profile_facts', id)) order by section desc, sort_order), '[]') into hero
      from firm_profile_facts where firm_id = f.id and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
    vq := case when public._visitor_checking(q) then 'claimed' when q.status = 'claimed' then 'queued' else q.status end;
    vs := case when public._visitor_checking(q) then q.claimed_at end;
    if not f.indexable and jsonb_array_length(hero) = 0 then
      select coalesce(jsonb_agg(jsonb_build_object('label', l, 'value', v, 'anchor', 'overview', 'src', '[]'::jsonb) order by o), '[]') into hero
        from (values (1, 'HQ', hq), (2, 'SEC CRD', nullif(q.sec_crd, '')), (3, 'LEI', nullif(q.lei, ''))) x(o, l, v) where v is not null;
    end if;
    return json_build_object('status', 'ok', 'open', false, 'locked', u->>'status', 'unchecked', not f.indexable,
      'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', hq, 'website', web, 'assets', assets),
      'hero', hero, 'sections', '[]'::json, 'done', _firm_checks_done(f.id),
      'checks', (select json_agg(json_build_object('n', n, 'title', title, 'descr', descr, 'state', null, 'count', null, 'searched_at', null,
          'items', null, 'itemized', null, 'name_only', null) order by n) from firm_check_rows where firm_id = f.id),
      'queue', vq, 'started_at', vs, 'details', null, 'outline', null,
      'ondemand', _ondemand_view(f.id, p_anon),
      'activity', public._firm_activity(f.id, open));
  end if;
  for s in select * from page_sections where enabled order by sort_order loop
    it := _sec_items(s.key, f.id);
    continue when jsonb_array_length(it) = 0;
    secs := secs || jsonb_build_object('key', s.key, 'title', s.title, 'subtitle', s.subtitle, 'renderer', s.renderer,
      'count', jsonb_array_length(it), 'unit', case when jsonb_array_length(it) = 1 then s.unit_one else s.unit_many end,
      'teaser', it->0->>'head', 'items', it);
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('label', hero_label, 'value', hero_value, 'anchor', section,
      'src', _src('firm_profile_facts', id)) order by section desc, sort_order), '[]') into hero
    from firm_profile_facts where firm_id = f.id and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
  vq := case when public._visitor_checking(q) then 'claimed' when q.status = 'claimed' then 'queued' else q.status end;
  vs := case when public._visitor_checking(q) then q.claimed_at end;
  return json_build_object('status', 'ok', 'open', true, 'unchecked', false, 'done', _firm_checks_done(f.id),
    'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', hq, 'website', web, 'assets', assets),
    'hero', hero, 'sections', secs,
    'checks', (select json_agg(json_build_object('n', n, 'title', title, 'descr', descr,
        'state', case when coalesce(cardinality(name_only), 0) > 0 and state in ('nc', 'clear', 'nf') then 'clear' else state end,
        'count', count_label,
        'searched_at', coalesce(searched_at, case when state <> 'nc' and f.report_date is not null then (f.report_date + time '12:00') at time zone 'America/Los_Angeles' end),
        'items', (select coalesce(json_agg(json_build_object('title', i.title, 'year', i.yr, 'status', i.status, 'note', i.note, 'who', i.who, 'court', i.court, 'url', i.src_url, 'src', i.src_label) order by i.yr desc nulls last, i.title), '[]') from check_row_items(firm_id, source_submission, n) i),
        'itemized', (select count(*) from check_row_items(firm_id, source_submission, n)),
        'name_only', case when coalesce(cardinality(name_only), 0) > 0 and state in ('nc', 'clear', 'nf') then to_json(name_only) else null end
        ) order by n) from firm_check_rows where firm_id = f.id),
    'queue', vq, 'started_at', vs,
    'details', u->'details', 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon),
      'activity', public._firm_activity(f.id, open));
end $function$;
