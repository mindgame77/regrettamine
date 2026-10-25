-- Checking view: a normal-lane claim older than 6 hours, with no open paid or request
-- job, is not shown as Checking. The queue row is left claimed; research_claim still
-- releases it. A page view does not write the queue. A paid or request claim keeps
-- showing Checking, including after 6 hours, until that release.

create or replace function public._visitor_checking(q public.research_queue)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select q.registry_id is not null
     and q.status = 'claimed'
     and q.claimed_at is not null
     and not (
       q.claimed_at < now() - interval '6 hours'
       and coalesce(q.lane, 'normal') = 'normal'
       and not exists (
         select 1 from public.ondemand_jobs j
         where j.registry_id = q.registry_id
           and j.status in ('queued', 'in_progress')
       )
     );
$$;

revoke all on function public._visitor_checking(public.research_queue) from public, anon, authenticated;

create or replace function public.firm_page(p_slug text, p_anon uuid, p_spend boolean default false, p_email text default null)
returns json language plpgsql security definer set search_path = public as $$
declare f firms; u json; open boolean; secs jsonb := '[]'; s page_sections; it jsonb; hero jsonb; q research_queue; qid text;
  vq text; vs timestamptz;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  u := unlock_firm(p_slug, p_anon, p_spend, p_email);
  open := u->>'status' = 'ok';
  if u->>'status' not in ('ok', 'locked') then return u; end if;
  if not open then
    select coalesce(jsonb_agg(jsonb_build_object('label', hero_label, 'value', hero_value, 'anchor', section,
        'src', _src('firm_profile_facts', id)) order by section desc, sort_order), '[]') into hero
      from firm_profile_facts where firm_id = f.id and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
    qid := _firm_queue_id(f.id);
    if qid is not null then select * into q from research_queue where registry_id = qid; end if;
    vq := case when public._visitor_checking(q) then 'claimed' when q.status = 'claimed' then 'queued' else q.status end;
    vs := case when public._visitor_checking(q) then q.claimed_at end;
    if not f.indexable and jsonb_array_length(hero) = 0 then
      select coalesce(jsonb_agg(jsonb_build_object('label', l, 'value', v, 'anchor', 'overview', 'src', '[]'::jsonb) order by o), '[]') into hero
        from (values (1, 'HQ', f.hq), (2, 'SEC CRD', nullif(q.sec_crd, '')), (3, 'LEI', nullif(q.lei, ''))) x(o, l, v) where v is not null;
    end if;
    return json_build_object('status', 'ok', 'open', false, 'locked', u->>'status', 'unchecked', not f.indexable,
      'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', f.hq),
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
  qid := _firm_queue_id(f.id);
  if qid is not null then select * into q from research_queue where registry_id = qid; end if;
  vq := case when public._visitor_checking(q) then 'claimed' when q.status = 'claimed' then 'queued' else q.status end;
  vs := case when public._visitor_checking(q) then q.claimed_at end;
  return json_build_object('status', 'ok', 'open', true, 'unchecked', false, 'done', _firm_checks_done(f.id),
    'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', f.hq),
    'hero', hero, 'sections', secs,
    'checks', (select json_agg(json_build_object('n', n, 'title', title, 'descr', descr,
        'state', case when coalesce(cardinality(name_only), 0) > 0 and state in ('nc', 'clear', 'nf') then 'clear' else state end,
        'count', count_label, 'searched_at', searched_at,
        'items', (select coalesce(json_agg(json_build_object('title', i.title, 'year', i.yr, 'status', i.status, 'note', i.note, 'who', i.who) order by i.yr desc nulls last, i.title), '[]') from check_findings(source_submission) i where i.k = n),
        'itemized', (select count(*) from check_findings(source_submission) i where i.k = n),
        'name_only', case when coalesce(cardinality(name_only), 0) > 0 and state in ('nc', 'clear', 'nf') then to_json(name_only) else null end
        ) order by n) from firm_check_rows where firm_id = f.id),
    'queue', vq, 'started_at', vs,
    'details', u->'details', 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon));
end $$;
revoke all on function public.firm_page(text, uuid, boolean, text) from public;
grant execute on function public.firm_page(text, uuid, boolean, text) to anon, authenticated, service_role;

create or replace function public.firm_check_status(p_slug text)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare f firms; q research_queue; qid text; vq text; vs timestamptz;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  qid := _firm_queue_id(f.id);
  if qid is not null then select * into q from research_queue where registry_id = qid; end if;
  vq := case when public._visitor_checking(q) then 'claimed' when q.status = 'claimed' then 'queued' else q.status end;
  vs := case when public._visitor_checking(q) then q.claimed_at end;
  return json_build_object('status', 'ok', 'done', _firm_checks_done(f.id), 'total', 10,
    'complete', _firm_checks_done(f.id) >= 10, 'queue', vq, 'started_at', vs);
end $$;
