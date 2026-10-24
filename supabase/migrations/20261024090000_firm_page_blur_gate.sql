-- Blur A: a locked firm page carries no check results. 1 credit opens /vc/<slug>/ and /full/.
-- firm_page (locked): firm, hero SEC facts, the 10 check names (n/title/descr) and the progress count only.
-- firm_check_status: progress only (done/total/queue); the per-check states moved behind the unlock.
-- firm_case_outline: was only used by firm_page's locked branch; no longer callable by clients.
-- CREATE OR REPLACE keeps existing grants (firm_page, firm_check_status: anon + authenticated).
CREATE OR REPLACE FUNCTION public.firm_page(p_slug text, p_anon uuid, p_spend boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f firms; u json; open boolean; secs jsonb := '[]'; s page_sections; it jsonb; hero jsonb; q research_queue; qid text;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  u := unlock_firm(p_slug, p_anon, p_spend);
  open := u->>'status' = 'ok';
  if u->>'status' not in ('ok', 'locked') then return u; end if;
  if not open then
    -- Locked (blur A): only what every visitor may see: the firm, the SEC hero facts, the 10 check names and the progress count.
    -- No section list, counts, teasers, outline, states, counts or dates of any check; firm_details only on an unlocked page.
    select coalesce(jsonb_agg(jsonb_build_object('label', hero_label, 'value', hero_value, 'anchor', section,
        'src', _src('firm_profile_facts', id)) order by section desc, sort_order), '[]') into hero
      from firm_profile_facts where firm_id = f.id and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
    qid := _firm_queue_id(f.id);
    if qid is not null then select * into q from research_queue where registry_id = qid; end if;
    return json_build_object('status', 'ok', 'open', false, 'locked', u->>'status',
      'firm', json_build_object('slug', f.slug, 'name', f.name, 'short_name', f.short_name, 'hq', f.hq),
      'hero', hero, 'sections', '[]'::json, 'done', _firm_checks_done(f.id),
      'checks', (select json_agg(json_build_object('n', n, 'title', title, 'descr', descr, 'state', null, 'count', null, 'searched_at', null,
          'items', null, 'itemized', null) order by n) from firm_check_rows where firm_id = f.id),
      'queue', q.status, 'started_at', case when q.status = 'claimed' then q.claimed_at end, 'details', null, 'outline', null);
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
  qid := _firm_queue_id(f.id);
  if qid is not null then select * into q from research_queue where registry_id = qid; end if;
  return json_build_object('status', 'ok', 'open', true, 'done', _firm_checks_done(f.id),
    'firm', json_build_object('slug', f.slug, 'name', f.name, 'short_name', f.short_name, 'hq', f.hq),
    'hero', hero, 'sections', secs,
    'checks', (select json_agg(json_build_object('n', n, 'title', title, 'descr', descr, 'state', state, 'count', count_label, 'searched_at', searched_at,
        'items', (select coalesce(json_agg(json_build_object('title', i.title, 'year', i.yr, 'status', i.status, 'note', i.note, 'who', i.who) order by i.yr desc nulls last, i.title), '[]') from check_findings(source_submission) i where i.k = n),
        'itemized', (select count(*) from check_findings(source_submission) i where i.k = n)) order by n) from firm_check_rows where firm_id = f.id),
    'queue', q.status, 'started_at', case when q.status = 'claimed' then q.claimed_at end,
    'details', u->'details', 'outline', null);
end $function$
;

CREATE OR REPLACE FUNCTION public.firm_check_status(p_slug text)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f firms; q research_queue; qid text;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  qid := _firm_queue_id(f.id);
  if qid is not null then select * into q from research_queue where registry_id = qid; end if;
  return json_build_object('status', 'ok', 'done', _firm_checks_done(f.id), 'total', 10,
    'complete', _firm_checks_done(f.id) >= 10, 'queue', q.status, 'started_at', case when q.status = 'claimed' then q.claimed_at end);
end $function$
;

revoke execute on function public.firm_case_outline(text) from public, anon, authenticated;
