-- Opened Review rows list the cases and regulator actions already on file.
-- check_findings still reads the submission. When that list is empty, check_saved_items
-- reads firm_legal_items (active cases, and regulator rows whose status is an open probe
-- or a settled order). Nothing here updates research_submissions, firm_check_rows, or firm_legal_items.

drop function public.check_findings(bigint);

create function public.check_findings(p_sub bigint)
returns table (k int, title text, yr text, status text, note text, who text, court text, src_url text, src_label text)
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
      from lnk where cn <> 8 and _ck_finding(r) and public._rec_tier(p_sub, r) <> 'needs_source')
  select fnd.k,
         coalesce(v->>'caption', v->>'regulator', case when v->>'kind' = 'donation' then nullif(concat_ws(' → ', v->>'donor', v->>'recipient'), '') end,
                  v->>'list', v->>'title', v->>'name',
                  case when v ? 'theme' then initcap(replace(split_part(v->>'theme', '.', 2), '_', ' ')) end,
                  v->'subject'->>'name',
                  nullif(btrim(v->>'case'), ''), nullif(btrim(v->>'matter'), ''),
                  case when nullif(v->>'text', '') is not null then initcap(replace(nullif(v->>'kind', ''), '_', ' ')) end)::text,
         public._filed_year(v->>'filed_at')::text,
         nullif(nullif(v->>'status', ''), 'unknown')::text,
         coalesce(v->>'summary', v->>'allegation', v->>'note', v->>'text')::text,
         case when fnd.r->>'checklist_item' ~* ' x partner' and v->>'kind' is distinct from 'donation' then coalesce(v->>'donor', v->'subject'->>'name') end::text,
         nullif(btrim(v->>'court'), '')::text,
         src.src_url::text,
         case
           when src.src_url is null then null
           else public.source_label(substring(src.src_url from '://(?:www\.)?([^/]+)'), src.src_url)
         end::text
    from fnd
    cross join lateral (select coalesce(fnd.r->'value', '{}') v) x
    left join lateral (
      select e.elem->>'url' as src_url
        from jsonb_array_elements(public._rec_sources(p_sub, fnd.r)) e(elem)
       where coalesce(e.elem->>'url', '') ~* '^https?://'
       order by case when public.source_tier(e.elem->>'url') = 'trusted' then 0 else 1 end, e.elem->>'url'
       limit 1
    ) src on true;
end $$;

revoke all on function public.check_findings(bigint) from public, anon, authenticated;

-- Active cases already saved on the firm, plus regulator actions whose status is an open probe or a settled order.
-- "None filed", "No match", "Needs proof", "Worth knowing" and a parent-company row are not the firm's open item.
create function public.check_saved_items(p_firm uuid, p_n int)
returns table (k int, title text, yr text, status text, note text, who text, court text, src_url text, src_label text)
language sql stable security definer set search_path = public as $$
  select p_n,
         li.title,
         public._filed_year(nullif(btrim(li.year_label), '')),
         case when li.grp = 'case' then li.state else nullif(btrim(li.status_label), '') end,
         nullif(btrim(li.note), ''),
         null::text,
         nullif(btrim((regexp_match(coalesce(li.note, ''), '((?:N|S|E|W|C|M)\.D\. [A-Za-z.]+)'))[1]), ''),
         src.url,
         case
           when src.url is null then null
           else public.source_label(coalesce(nullif(btrim(src.label), ''), substring(src.url from '://(?:www\.)?([^/]+)')), src.url)
         end
    from public.firm_legal_items li
    left join lateral (
      select s.url, fs.label
        from public.fact_sources fs
        join public.sources s on s.id = fs.source_id
       where fs.fact_type = 'firm_legal_items' and fs.fact_id = li.id and coalesce(s.url, '') ~* '^https?://'
       order by fs.sort_order, s.url
       limit 1
    ) src on true
   where li.firm_id = p_firm
     and (
       (p_n in (6, 7) and li.grp = 'case' and li.state = 'Active'
         and coalesce(public._ck_non_us(jsonb_build_object('value', jsonb_build_object('court', li.note, 'jurisdiction', ''))), false) = (p_n = 7))
       or (p_n = 4 and li.grp = 'regulator'
         and coalesce(li.status_label, '') !~* '^(none|no match|needs proof|worth knowing|parent)'
         and coalesce(li.status_label, '') ~* 'open|probe|pending|settled|order')
     );
$$;

revoke all on function public.check_saved_items(uuid, int) from public, anon, authenticated;
grant execute on function public.check_saved_items(uuid, int) to service_role;

-- Submission findings win. Saved legal items fill the row only when that list is empty.
create function public.check_row_items(p_firm uuid, p_sub bigint, p_n int)
returns table (k int, title text, yr text, status text, note text, who text, court text, src_url text, src_label text)
language plpgsql stable security definer set search_path = public as $$
begin
  return query select * from public.check_findings(p_sub) i where i.k = p_n;
  if found then return; end if;
  return query select * from public.check_saved_items(p_firm, p_n);
end $$;

revoke all on function public.check_row_items(uuid, bigint, int) from public, anon, authenticated;
grant execute on function public.check_row_items(uuid, bigint, int) to service_role;

create or replace function public.firm_page(p_slug text, p_anon uuid, p_spend boolean default false, p_email text default null)
returns json language plpgsql security definer set search_path = public as $$
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
      'ondemand', _ondemand_view(f.id, p_anon));
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
    'details', u->'details', 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon));
end $$;

revoke all on function public.firm_page(text, uuid, boolean, text) from public;
grant execute on function public.firm_page(text, uuid, boolean, text) to anon, authenticated, service_role;
