-- Lightspeed /vc/lightspeed/ returned 500 (57014 statement timeout, anon limit 3s).
-- firm_page called _lab_live_pill(firm, n) per check row, and each call re-ran check_findings(sub)
-- (twice for checks 4 and 6). firm_page already materializes those findings in cf.
-- This adds _lab_live_pill(p_firm, p_n, p_fin, p_hot), which takes the precomputed counts, and has
-- firm_page pass them from cf. The 2-argument _lab_live_pill is unchanged for other callers.
-- Rollback: supabase/rollbacks/20261028210000_firm_page_pill_counts.sql

CREATE OR REPLACE FUNCTION public._lab_live_pill(p_firm uuid, p_n integer, p_fin integer, p_hot integer)
 RETURNS TABLE(state text, count_label text, why text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare
  looked boolean; sub bigint; fin int := 0; sav int := 0; items int := 0; hot int := 0;
  iapd text; v_state text; v_count text; v_why text; stored_st text; stored_cnt text;
begin
  select (r.searched_at is not null or r.checked_on is not null), r.source_submission, r.state, r.count_label
    into looked, sub, stored_st, stored_cnt
  from firm_check_rows r where r.firm_id = p_firm and r.n = p_n;
  if not found then
    return query select 'nc'::text, null::text, 'no check row'::text;
    return;
  end if;
  -- p_fin: findings for (sub, p_n) precomputed by the caller (0 when sub is null). null = compute here.
  if p_fin is not null then fin := p_fin;
  elsif sub is not null then
    select count(*)::int into fin from check_findings(sub) c where c.k = p_n;
  end if;
  select count(*)::int into sav from check_saved_items(p_firm, p_n);
  items := case when fin > 0 then fin else sav end;
  if p_n = 8 then
    select v.value->>'value' into iapd
    from vc_source_facts v
    where v.firm_id = p_firm and v.superseded_by is null
      and v.value->>'field' = 'registration_status'
      and coalesce(v.source_url, '') ~* 'adviserinfo\.sec\.gov|sec\.gov'
      and coalesce(v.value->>'value', '') !~* 'separate adviser|relying adviser'
      and coalesce(v.value->>'value', '') ~* 'SEC-registered|Exempt reporting|\mERA\M|Registered, Approved|status Approved'
    order by v.retrieved_at desc nulls last
    limit 1;
    if iapd is null then
      select p.value into iapd
      from firm_profile_facts p
      join fact_sources fs on fs.fact_type = 'firm_profile_facts' and fs.fact_id = p.id
      join sources s on s.id = fs.source_id and s.url ~* 'adviserinfo\.sec\.gov'
      where p.firm_id = p_firm and not p.hidden
        and p.value ~* 'SEC-registered|Exempt Reporting Adviser|Exempt reporting adviser'
      order by p.sort_order
      limit 1;
    end if;
    if iapd is not null then
      v_state := 'clear'; v_count := null; v_why := 'IAPD registration row';
    else
      v_state := 'nc'; v_count := null; v_why := 'no IAPD registration row';
    end if;
  elsif items > 0 and p_n = 6 then
    if fin > 0 and p_hot is not null then
      hot := p_hot;
    elsif fin > 0 then
      select count(*)::int into hot from check_findings(sub) c
       where c.k = 6 and coalesce(c.status, '') ~* 'active|open|pending|ongoing'
         and coalesce(c.status, '') !~* '^(dismissed|closed|settled|withdrawn)';
    else
      select count(*)::int into hot from check_saved_items(p_firm, 6) c
       where coalesce(c.status, '') ~* 'active|open|pending|ongoing'
         and coalesce(c.status, '') !~* '^(dismissed|closed|settled|withdrawn)';
    end if;
    if hot > 0 then v_state := 'review'; v_why := 'a finding is active, open, or pending';
    else v_state := 'wk'; v_why := 'findings are closed cases'; end if;
    if hot > 0 and hot = items then
      v_count := case when items = 1 then '1 active case' else items::text || ' active cases' end;
    else
      v_count := case when items = 1 then '1 case' else items::text || ' cases' end;
    end if;
  elsif items > 0 and p_n = 4 then
    v_state := 'review';
    if fin > 0 and p_hot is not null then
      hot := p_hot;
    elsif fin > 0 then
      select count(*)::int into hot from check_findings(sub) c
       where c.k = 4 and coalesce(c.status, '') ~* 'open|probe' and coalesce(c.status, '') !~* 'settled|closed';
    else
      select count(*)::int into hot from check_saved_items(p_firm, 4) c
       where coalesce(c.status, '') ~* 'open|probe' and coalesce(c.status, '') !~* 'settled|closed';
    end if;
    if hot > 0 then
      v_count := case when hot = 1 then '1 open probe' else hot::text || ' open probes' end;
      v_why := 'open regulator findings';
    else
      v_count := case when items = 1 then '1 action' else items::text || ' actions' end;
      v_why := 'regulator findings';
    end if;
  elsif items > 0 and p_n = 10 then
    v_state := 'wk'; v_count := case when items = 1 then '1 record' else items::text || ' records' end; v_why := 'political-tie findings';
  elsif items > 0 and p_n = 9 then
    v_state := 'review'; v_count := case when items = 1 then '1 finding' else items::text || ' findings' end; v_why := 'people-screen findings';
  elsif items > 0 and p_n = 7 then
    v_state := 'clear'; v_count := case when items = 1 then '1 non-party mention' else items::text || ' non-party mentions' end; v_why := 'non-US findings';
  elsif items > 0 then
    v_state := 'review'; v_count := case when items = 1 then '1 record' else items::text || ' records' end; v_why := 'findings on this check';
  elsif looked then
    v_state := case when p_n = 10 then 'nf' else 'clear' end; v_count := null; v_why := 'searched, no findings';
  else
    v_state := 'nc'; v_count := null; v_why := 'no findings and this check was not searched';
  end if;
  if v_state = stored_st and stored_cnt is not null and v_count is not null
     and (select count(*) from regexp_matches(stored_cnt, '\d+', 'g')) = 1
     and (regexp_match(stored_cnt, '\d+'))[1] = (regexp_match(v_count, '\d+'))[1]
  then v_count := stored_cnt; end if;
  return query select v_state, v_count, v_why;
end $function$;

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
      'checks', (select json_agg(json_build_object('n', n, 'title', title, 'descr', descr, 'state', null, 'count', null, 'searched_at', null, 'items', null, 'itemized', null, 'name_only', null) order by n) from firm_check_rows where firm_id = f.id),
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
    'checks', (with cf as materialized (select d.s, c.* from (select distinct source_submission as s from firm_check_rows where firm_id = f.id) d cross join lateral check_findings(d.s) c)
      select json_agg(json_build_object('n', r.n, 'title', r.title, 'descr', r.descr,
        'state', case when lp.state is not null and coalesce(cardinality(r.name_only), 0) > 0 and lp.state in ('nc', 'clear', 'nf') then 'clear' when lp.state is not null then lp.state when coalesce(cardinality(r.name_only), 0) > 0 and r.state in ('nc', 'clear', 'nf') then 'clear' else r.state end,
        'count', case when lp.state is not null then lp.count_label else r.count_label end,
        'searched_at', coalesce(r.searched_at, case when r.state <> 'nc' and f.report_date is not null then (f.report_date + time '12:00') at time zone 'America/Los_Angeles' end),
        'items', x.items, 'itemized', x.cnt,
        'name_only', case when coalesce(cardinality(r.name_only), 0) > 0 and r.state in ('nc', 'clear', 'nf') then to_json(r.name_only) else null end) order by r.n)
       from firm_check_rows r
       cross join lateral (select coalesce(json_agg(json_build_object('title', i.title, 'year', i.yr, 'status', i.status, 'note', i.note, 'who', i.who, 'court', i.court, 'url', i.src_url, 'src', i.src_label) order by i.yr desc nulls last, i.title), '[]') as items, count(*) as cnt
          from (select g.title, g.yr, g.status, g.note, g.who, g.court, g.src_url, g.src_label from cf g where g.s is not distinct from r.source_submission and g.k = r.n
                union all select v.title, v.yr, v.status, v.note, v.who, v.court, v.src_url, v.src_label from check_saved_items(r.firm_id, r.n) v
                 where not exists (select 1 from cf g where g.s is not distinct from r.source_submission and g.k = r.n)) i) x
      left join lateral public._lab_live_pill(r.firm_id, r.n,
        case when r.source_submission is null then 0
             else (select count(*)::int from cf g where g.s = r.source_submission and g.k = r.n) end,
        case when r.source_submission is null then 0
             when r.n = 6 then (select count(*)::int from cf g where g.s = r.source_submission and g.k = 6
                and coalesce(g.status, '') ~* 'active|open|pending|ongoing' and coalesce(g.status, '') !~* '^(dismissed|closed|settled|withdrawn)')
             when r.n = 4 then (select count(*)::int from cf g where g.s = r.source_submission and g.k = 4
                and coalesce(g.status, '') ~* 'open|probe' and coalesce(g.status, '') !~* 'settled|closed')
             else 0 end) lp on public._lab_firm(f.id)
      where r.firm_id = f.id),
    'queue', vq, 'started_at', vs, 'details', u->'details', 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon), 'activity', public._firm_activity(f.id, open));
end $function$;
