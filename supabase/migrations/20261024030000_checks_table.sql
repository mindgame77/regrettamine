-- Checks table (mockup option 3, approved 2026-10-23): per-check itemized findings for the firm page.
-- check_findings(sid) lists exactly the records checks_from_submission() counts (same CTEs, copied verbatim), so a
-- row's itemized list matches its count when the row came from that upload. Uploads are only read.
-- firm_page: each check gets 'itemized' (count, always) and 'items' (only when the page is unlocked, like 'details').
create or replace function public.check_findings(p_sub bigint)
returns table (k int, title text, yr text, status text, note text, who text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare p jsonb;
begin
  if p_sub is null then return; end if;
  select s.payload into p from research_submissions s where s.id = p_sub and s.valid;
  if p is null then return; end if;
  return query
  with cov as (
    select c, _ck_n(c->>'checklist_item') cn, c->>'status' st, position(':' in coalesce(c->>'checklist_item', '')) > 0 sub,
           coalesce(substring(lower(split_part(c->>'checklist_item', ':', 1)) from ' x ([a-z]+)'), 'firm') scope
      from jsonb_array_elements(case when jsonb_typeof(p->'coverage') = 'array' then p->'coverage' else '[]' end) c),
  covm as (select * from cov where cn is not null),
  rec as (select r->>'record_id' rid, r from jsonb_array_elements(case when jsonb_typeof(p->'records') = 'array' then p->'records' else '[]' end) r),
  lg as (select q->>'query_id' qid, q from jsonb_array_elements(case when jsonb_typeof(p->'search_log') = 'array' then p->'search_log' else '[]' end) q),
  item_recs as (select covm.c, rec.r from covm
      cross join lateral jsonb_array_elements_text(case when jsonb_typeof(covm.c->'record_ids') = 'array' then covm.c->'record_ids' else '[]' end) x(rid)
      join rec on rec.rid = x.rid),
  lnk as (
    select covm.cn, rec.rid, rec.r from covm
      cross join lateral jsonb_array_elements_text(case when jsonb_typeof(covm.c->'record_ids') = 'array' then covm.c->'record_ids' else '[]' end) x(rid)
      join rec on rec.rid = x.rid
     where covm.st = 'records'
    union
    select _ck_n(r->>'checklist_item'), rid, r from rec where _ck_n(r->>'checklist_item') is not null),
  fnd as (
    select distinct on (k, rid) case when cn = 6 and _ck_non_us(r) then 7 else cn end k, rid, r,
           lower(coalesce(r->'value'->>'severity', '')) sev, lower(coalesce(r->'value'->>'status', '')) rst
      from lnk where cn <> 8 and _ck_finding(r))
  select fnd.k,
         coalesce(v->>'caption', v->>'regulator', case when v->>'kind' = 'donation' then nullif(concat_ws(' → ', v->>'donor', v->>'recipient'), '') end,
                  v->>'list', v->>'title', v->>'name',
                  case when v ? 'theme' then initcap(replace(split_part(v->>'theme', '.', 2), '_', ' ')) end,
                  v->'subject'->>'name')::text,
         left(coalesce(v->>'filed_at', v->>'date', v->>'event_date', v->>'cycle', v->>'first_reported'), 4)::text,
         nullif(nullif(v->>'status', ''), 'unknown')::text,
         coalesce(v->>'summary', v->>'allegation', v->>'note')::text,
         case when fnd.r->>'checklist_item' ~* ' x partner' and v->>'kind' is distinct from 'donation' then coalesce(v->>'donor', v->'subject'->>'name') end::text
    from fnd cross join lateral (select coalesce(fnd.r->'value', '{}') v) x;
end $$;
revoke all on function public.check_findings(bigint) from public, anon, authenticated;

create or replace function public.firm_page(p_slug text, p_anon uuid, p_spend boolean default false)
 returns json language plpgsql security definer set search_path to 'public' as $function$
declare f firms; u json; open boolean; secs jsonb := '[]'; s page_sections; it jsonb; hero jsonb; q research_queue; qid text;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and launch_page;
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  u := unlock_firm(p_slug, p_anon, p_spend);
  open := u->>'status' = 'ok';
  if u->>'status' not in ('ok', 'locked') then return u; end if;
  for s in select * from page_sections where enabled order by sort_order loop
    it := _sec_items(s.key, f.id);
    continue when jsonb_array_length(it) = 0;
    secs := secs || jsonb_build_object('key', s.key, 'title', s.title, 'subtitle', s.subtitle, 'renderer', s.renderer,
      'count', jsonb_array_length(it), 'unit', case when jsonb_array_length(it) = 1 then s.unit_one else s.unit_many end,
      'teaser', it->0->>'head', 'items', case when open then it end);
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('label', hero_label, 'value', hero_value, 'anchor', section,
      'src', _src('firm_profile_facts', id)) order by section desc, sort_order), '[]') into hero
    from firm_profile_facts where firm_id = f.id and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
  qid := _firm_queue_id(f.id);
  if qid is not null then select * into q from research_queue where registry_id = qid; end if;
  return json_build_object('status', 'ok', 'open', open,
    'firm', json_build_object('slug', f.slug, 'name', f.name, 'short_name', f.short_name, 'hq', f.hq),
    'hero', hero, 'sections', secs,
    'checks', (select json_agg(json_build_object('n', n, 'title', title, 'descr', descr, 'state', state, 'count', count_label, 'searched_at', searched_at,
        'items', case when open then (select coalesce(json_agg(json_build_object('title', i.title, 'year', i.yr, 'status', i.status, 'note', i.note, 'who', i.who) order by i.yr desc nulls last, i.title), '[]') from check_findings(source_submission) i where i.k = n) end,
        'itemized', (select count(*) from check_findings(source_submission) i where i.k = n)) order by n) from firm_check_rows where firm_id = f.id),
    'queue', q.status, 'started_at', case when q.status = 'claimed' then q.claimed_at end,
    'details', u->'details', 'outline', case when not open then firm_case_outline(p_slug) end);
end $function$;
