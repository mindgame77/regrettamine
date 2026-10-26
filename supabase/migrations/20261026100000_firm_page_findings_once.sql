-- firm_page: check_findings(submission) runs once per firm instead of once per check row (check_row_items
-- recomputed every finding and kept one row's). Same result as check_row_items: a row's findings when it has
-- any, else its saved items. Nothing visible changes.

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
    'checks', (with cf as materialized (select d.s, c.* from (select distinct source_submission as s from firm_check_rows where firm_id = f.id) d
                                          cross join lateral check_findings(d.s) c)
      select json_agg(json_build_object('n', r.n, 'title', r.title, 'descr', r.descr,
        'state', case when coalesce(cardinality(r.name_only), 0) > 0 and r.state in ('nc', 'clear', 'nf') then 'clear' else r.state end,
        'count', r.count_label,
        'searched_at', coalesce(r.searched_at, case when r.state <> 'nc' and f.report_date is not null then (f.report_date + time '12:00') at time zone 'America/Los_Angeles' end),
        'items', x.items,
        'itemized', x.cnt,
        'name_only', case when coalesce(cardinality(r.name_only), 0) > 0 and r.state in ('nc', 'clear', 'nf') then to_json(r.name_only) else null end
        ) order by r.n)
       from firm_check_rows r
       cross join lateral (select coalesce(json_agg(json_build_object('title', i.title, 'year', i.yr, 'status', i.status, 'note', i.note, 'who', i.who, 'court', i.court, 'url', i.src_url, 'src', i.src_label) order by i.yr desc nulls last, i.title), '[]') as items, count(*) as cnt
                             from (select g.title, g.yr, g.status, g.note, g.who, g.court, g.src_url, g.src_label from cf g
                                    where g.s is not distinct from r.source_submission and g.k = r.n
                                   union all
                                   select v.title, v.yr, v.status, v.note, v.who, v.court, v.src_url, v.src_label from check_saved_items(r.firm_id, r.n) v
                                    where not exists (select 1 from cf g where g.s is not distinct from r.source_submission and g.k = r.n)) i) x
      where r.firm_id = f.id),
    'queue', vq, 'started_at', vs,
    'details', u->'details', 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon),
      'activity', public._firm_activity(f.id, open));
end $function$;
