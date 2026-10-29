-- Rollback of 20261029120000_firm_social_pills.sql: firm_page exactly as live before (20261029031000_checks_off.sql),
-- then the helper is dropped and cached pages cleared.
CREATE OR REPLACE FUNCTION public.firm_page(p_slug text, p_anon uuid, p_spend boolean DEFAULT false, p_email text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
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
    select coalesce(jsonb_agg(jsonb_build_object('label', hero_label, 'value', hero_value, 'anchor', section, 'src', _src('firm_profile_facts', id)) order by section desc, sort_order), '[]') into hero
      from firm_profile_facts where firm_id = f.id and not hidden and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
    vq := case when public._visitor_checking(q) then 'claimed' when q.status = 'claimed' then 'queued' else q.status end;
    vs := case when public._visitor_checking(q) then q.claimed_at end;
    if not f.indexable and jsonb_array_length(hero) = 0 then
      select coalesce(jsonb_agg(jsonb_build_object('label', l, 'value', v, 'anchor', 'overview', 'src', '[]'::jsonb) order by o), '[]') into hero
        from (values (1, 'HQ', hq), (2, 'SEC CRD', nullif(q.sec_crd, '')), (3, 'LEI', nullif(q.lei, ''))) x(o, l, v) where v is not null;
    end if;
    return json_build_object('status', 'ok', 'open', false, 'locked', u->>'status', 'unchecked', not f.indexable,
      'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', hq, 'website', web, 'assets', assets),
      'hero', hero, 'sections', '[]'::json, 'done', _firm_checks_done(f.id),
      'checks', (select json_agg(json_build_object('n', e->'n', 'title', e->'title', 'descr', e->'descr', 'state', null, 'count', null, 'searched_at', null, 'items', null, 'itemized', null, 'name_only', null)) from json_array_elements(public._check_placeholders()) e),
      'queue', vq, 'started_at', vs, 'details', null, 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon), 'activity', public._firm_activity(f.id, open));
  end if;
  for s in select * from page_sections where enabled order by sort_order loop
    it := _sec_items(s.key, f.id);
    continue when jsonb_array_length(it) = 0;
    secs := secs || jsonb_build_object('key', s.key, 'title', s.title, 'subtitle', s.subtitle, 'renderer', s.renderer,
      'count', jsonb_array_length(it), 'unit', case when jsonb_array_length(it) = 1 then s.unit_one else s.unit_many end,
      'teaser', it->0->>'head', 'items', it);
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('label', hero_label, 'value', hero_value, 'anchor', section, 'src', _src('firm_profile_facts', id)) order by section desc, sort_order), '[]') into hero
    from firm_profile_facts where firm_id = f.id and not hidden and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
  vq := case when public._visitor_checking(q) then 'claimed' when q.status = 'claimed' then 'queued' else q.status end;
  vs := case when public._visitor_checking(q) then q.claimed_at end;
  return json_build_object('status', 'ok', 'open', true, 'unchecked', false, 'done', _firm_checks_done(f.id),
    'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', hq, 'website', web, 'assets', assets),
    'hero', hero, 'sections', secs,
    'checks', public._firm_checks(f.id),
    'queue', vq, 'started_at', vs, 'details', u->'details', 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon), 'activity', public._firm_activity(f.id, open));
end $function$;

drop function if exists public._firm_social(uuid);
delete from public.firm_page_cache;
