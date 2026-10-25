-- Display-only fields for the firm header and the Date searched column.
-- Nothing here rewrites bot payloads, fact rows, or firm_check_rows.
-- HQ / website / assets are derived when the page is read. A check with no
-- searched_at shows the firm's report date (noon Pacific) instead of a dash.
-- check_findings years come only from a real filed_at that is not in the future.

create or replace function public._filed_year(p text)
returns text
language plpgsql
stable
set search_path = public
as $$
declare d date; y int;
begin
  if p is null then return null; end if;
  if p ~ '^\d{4}-\d{2}-\d{2}' then
    begin
      d := substring(p from 1 for 10)::date;
    exception when others then
      return null;
    end;
    if d > (timezone('America/Los_Angeles', now()))::date then return null; end if;
    return to_char(d, 'YYYY');
  end if;
  if p ~ '^\d{4}$' then
    y := p::int;
    if y > extract(year from timezone('America/Los_Angeles', now()))::int then return null; end if;
    return p;
  end if;
  return null;
end $$;

revoke all on function public._filed_year(text) from public, anon, authenticated;

-- The firm's own site: the primary domain, else a homepage URL cited on the firm.
-- A host that also appears in a profile fact is preferred. Social, court and filing hosts are not the firm's site.
create or replace function public._firm_website(p_firm uuid, p_domain text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  with raw as (
    select 0 as pri, case when btrim(p_domain) ~* '^https?://' then btrim(p_domain) else 'https://' || btrim(p_domain) end as url
      where nullif(btrim(p_domain), '') is not null
    union all
    select 1, s.url from fact_sources fs join sources s on s.id = fs.source_id
      where fs.firm_id = p_firm and s.url ~* '^https?://'
    union all
    select 2, m[1] from firm_profile_facts f
      cross join lateral regexp_matches(coalesce(f.value, ''), $re$https?://[^[:space:]<>"')]+$re$, 'gi') as m
      where f.firm_id = p_firm
    union all
    select 3, q.website from research_queue q
      where q.registry_id = public._firm_queue_id(p_firm) and q.website ~* '^https?://'
  ),
  host as (
    select pri, url,
      lower(regexp_replace(split_part(regexp_replace(regexp_replace(url, '[.,;:]+$', ''), '^https?://', '', 'i'), '/', 1), '^www\.', '')) as host,
      regexp_replace(regexp_replace(regexp_replace(regexp_replace(url, '[.,;:]+$', ''), '^https?://[^/]+', '', 'i'), '[?#].*$', ''), '/+$', '') as path
    from raw
  ),
  ok as (
    select * from host
    where host ~ '^[a-z0-9.-]+\.[a-z]{2,}$'
      and host !~ '(^|\.)(sec\.gov|instagram\.com|linkedin\.com|twitter\.com|x\.com|facebook\.com|fb\.com|youtube\.com|medium\.com|courtlistener\.com|pacermonitor\.com|wikipedia\.org|crunchbase\.com|t\.co)$'
  )
  select 'https://' || o.host || '/'
    from ok o
   order by
     case when o.pri = 0 then 0 else 1 end,
     case when o.path = '' then 0 else 1 end,
     case when o.pri = 0 or exists (
       select 1 from firm_profile_facts f
        where f.firm_id = p_firm and position(o.host in lower(f.value)) > 0
     ) then 0 else 1 end,
     o.pri
   limit 1;
$$;

revoke all on function public._firm_website(uuid, text) from public, anon, authenticated;

-- Regulatory AUM from a profile fact that cites Item 5F (or regulatory AUM), else aum_display
-- when that column is already a dollar figure. Schedule D gross assets are not Assets.
create or replace function public._firm_assets(p_firm uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select (regexp_match(f.value, '\$[0-9][0-9,]*\.[0-9]+|\$[0-9][0-9,]*'))[1]
       from firm_profile_facts f
      where f.firm_id = p_firm
        and f.value ~* '(item[[:space:]]*5[[:space:]]*f|regulatory[[:space:]]+aum|regulatory[[:space:]]+assets)'
        and f.value !~* 'schedule[[:space:]]*d|gross[[:space:]]+asset'
        and f.value ~ '\$[0-9]'
      order by case when f.value ~* 'item[[:space:]]*5[[:space:]]*f' then 0 else 1 end, f.sort_order
      limit 1),
    (select fi.aum_display from firms fi where fi.id = p_firm and fi.aum_display ~ '^\$')
  );
$$;

revoke all on function public._firm_assets(uuid) from public, anon, authenticated;

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
      from lnk where cn <> 8 and _ck_finding(r) and public._rec_tier(p_sub, r) <> 'needs_source')
  select fnd.k,
         coalesce(v->>'caption', v->>'regulator', case when v->>'kind' = 'donation' then nullif(concat_ws(' → ', v->>'donor', v->>'recipient'), '') end,
                  v->>'list', v->>'title', v->>'name',
                  case when v ? 'theme' then initcap(replace(split_part(v->>'theme', '.', 2), '_', ' ')) end,
                  v->'subject'->>'name',
                  case when nullif(v->>'text', '') is not null then initcap(replace(nullif(v->>'kind', ''), '_', ' ')) end)::text,
         public._filed_year(v->>'filed_at')::text,
         nullif(nullif(v->>'status', ''), 'unknown')::text,
         coalesce(v->>'summary', v->>'allegation', v->>'note', v->>'text')::text,
         case when fnd.r->>'checklist_item' ~* ' x partner' and v->>'kind' is distinct from 'donation' then coalesce(v->>'donor', v->'subject'->>'name') end::text
    from fnd cross join lateral (select coalesce(fnd.r->'value', '{}') v) x;
end $$;

revoke all on function public.check_findings(bigint) from public, anon, authenticated;

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
        'items', (select coalesce(json_agg(json_build_object('title', i.title, 'year', i.yr, 'status', i.status, 'note', i.note, 'who', i.who) order by i.yr desc nulls last, i.title), '[]') from check_findings(source_submission) i where i.k = n),
        'itemized', (select count(*) from check_findings(source_submission) i where i.k = n),
        'name_only', case when coalesce(cardinality(name_only), 0) > 0 and state in ('nc', 'clear', 'nf') then to_json(name_only) else null end
        ) order by n) from firm_check_rows where firm_id = f.id),
    'queue', vq, 'started_at', vs,
    'details', u->'details', 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon));
end $$;

revoke all on function public.firm_page(text, uuid, boolean, text) from public;
grant execute on function public.firm_page(text, uuid, boolean, text) to anon, authenticated, service_role;
