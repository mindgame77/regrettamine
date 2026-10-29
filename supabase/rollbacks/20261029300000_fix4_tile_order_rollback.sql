-- Rollback fix 4: restore firm_page and _route_aum_record; drop the money-tile helper. The source-url columns and
-- their checks are kept (data, not code); the page no longer reads them.

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
      'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', hq, 'website', web, 'assets', assets, 'social', public._firm_social(f.id), 'founded_year', f.founded_year),
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
    'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', hq, 'website', web, 'assets', assets, 'social', public._firm_social(f.id), 'founded_year', f.founded_year),
    'hero', hero, 'sections', secs,
    'checks', public._firm_checks(f.id),
    'queue', vq, 'started_at', vs, 'details', u->'details', 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon), 'activity', public._firm_activity(f.id, open));
end $function$
;

CREATE OR REPLACE FUNCTION public._route_aum_record(p_firm uuid, qid text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bots', 'public'
AS $function$
declare rec record; v jsonb; a numeric; c text; fa numeric; n int := 0; why text;
begin
  if qid is null then return 0; end if;
  select s.id sub, r.value r into rec from research_submissions s, jsonb_array_elements(coalesce(s.payload->'records', '[]')) r
   where s.registry_id = qid and s.valid and r->>'field_path' = 'aum'
     and exists (select 1 from jsonb_array_elements(public._rec_sources(s.id, r)) x where coalesce(x->>'url', '') like 'http%' and public._promo_src_ok(x->>'url'))
   order by s.received_at desc, s.id desc limit 1;
  if rec.sub is null then return 0; end if;
  v := rec.r->'value';
  if jsonb_typeof(v) <> 'object' then return 0; end if;
  if lower(coalesce(v->>'basis', '')) = 'press' then return 0; end if;  -- A7.3
  if jsonb_typeof(v->'amount_usd') = 'number' then a := (v->>'amount_usd')::numeric; c := 'USD';
  elsif jsonb_typeof(v->'amount') = 'number' and public._money_iso(upper(v->>'currency')) then a := (v->>'amount')::numeric; c := upper(v->>'currency');
  elsif jsonb_typeof(v->'raum_usd') = 'number' then a := (v->>'raum_usd')::numeric; c := 'USD';
  end if;
  if jsonb_typeof(v->'private_fund_gav_usd') = 'number' then fa := (v->>'private_fund_gav_usd')::numeric; end if;
  if a is not null and (a < 1000 or a <> trunc(a)) then a := null; end if;   -- A15.8: full numbers only
  if fa is not null and (fa < 1000 or fa <> trunc(fa)) then fa := null; end if;
  if a is not null then
    update firms set aum_amount = a, aum_currency = c where id = p_firm and aum_amount is null;
    if found then n := n + 1; why := null; else why := 'firm already has an AUM in firms.aum_amount; kept the existing value (fix 3)'; end if;
    insert into publish_checks(origin, origin_id, firm_id, section, kind, field, item, outcome, reason, target_table, target_id)
    values ('submission', rec.sub, p_firm, 'funds', 'record', 'aum', rec.r, case when why is null then 'published' else 'rejected' end, why, 'firms', p_firm);
  end if;
  if fa is not null then
    update firms set fund_assets_amount = fa, fund_assets_currency = 'USD' where id = p_firm and fund_assets_amount is null;
    if found then n := n + 1; end if;
  end if;
  if n > 0 then delete from firm_page_cache where firm_id = p_firm; end if;
  return n;
end $function$
;

drop function if exists public._firm_money_tiles(uuid);
delete from public.firm_page_cache where firm_id in (select id from public.firms where public._lab_firm(id));
-- Front end: revert launch/js/company.js and launch/copy.json from the fix 4 commit (git revert).
