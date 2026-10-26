-- firm_page speed (big firms like YC): the page payload carries only the first slice of the activity lists
-- (latest deal + latest founder review + exact counts). The full lists load on demand through
-- firm_activity_list() when "Show all" opens, with the same unlock check. check_row_items runs once per check row.
-- Nothing visible changes.

create index if not exists investments_firm_real_date_idx on public.investments (firm_id, invested_on desc nulls last) where data_status = 'real';
create index if not exists reviews_firm_founder_idx on public.reviews (firm_id, reviewed_on desc nulls last) where review_type = 'founder' and is_public and moderation_status = 'approved';
create index if not exists funds_firm_real_closed_idx on public.funds (firm_id, closed_on desc nulls last) where data_status = 'real';

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
   where r.firm_id = p_firm and r.review_type = 'founder' and r.is_public and r.moderation_status = 'approved';
  select _activity_review(r, c) into r0
    from reviews r left join portfolio_companies c on c.id = r.company_id
   where r.firm_id = p_firm and r.review_type = 'founder' and r.is_public and r.moderation_status = 'approved'
   order by r.reviewed_on desc nulls last, r.created_at desc limit 1;

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

-- Full deal or founder-review list for one firm, for the "Show all" popup. Same unlock rule as firm_page
-- (a spend on this firm by this visitor's balance); never spends. kind: 'deals' | 'revs'.
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
    select coalesce(jsonb_agg(_activity_review(r, c) order by r.reviewed_on desc nulls last, r.created_at desc), '[]') into out
      from reviews r left join portfolio_companies c on c.id = r.company_id
     where r.firm_id = f and r.review_type = 'founder' and r.is_public and r.moderation_status = 'approved';
  else
    return json_build_object('status', 'bad_kind');
  end if;
  return json_build_object('status', 'ok', 'items', out);
end $function$;

revoke all on function public.firm_activity_list(text, uuid, text) from public;
grant execute on function public.firm_activity_list(text, uuid, text) to anon, authenticated;

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
    'checks', (select json_agg(json_build_object('n', r.n, 'title', r.title, 'descr', r.descr,
        'state', case when coalesce(cardinality(r.name_only), 0) > 0 and r.state in ('nc', 'clear', 'nf') then 'clear' else r.state end,
        'count', r.count_label,
        'searched_at', coalesce(r.searched_at, case when r.state <> 'nc' and f.report_date is not null then (f.report_date + time '12:00') at time zone 'America/Los_Angeles' end),
        'items', x.items,
        'itemized', x.cnt,
        'name_only', case when coalesce(cardinality(r.name_only), 0) > 0 and r.state in ('nc', 'clear', 'nf') then to_json(r.name_only) else null end
        ) order by r.n)
       from firm_check_rows r
       cross join lateral (select coalesce(json_agg(json_build_object('title', i.title, 'year', i.yr, 'status', i.status, 'note', i.note, 'who', i.who, 'court', i.court, 'url', i.src_url, 'src', i.src_label) order by i.yr desc nulls last, i.title), '[]') as items, count(*) as cnt
                             from check_row_items(r.firm_id, r.source_submission, r.n) i) x
      where r.firm_id = f.id),
    'queue', vq, 'started_at', vs,
    'details', u->'details', 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon),
      'activity', public._firm_activity(f.id, open));
end $function$;
