-- Lab firms: check pills and My firms tallies are computed when the page is read.
-- Check 8 uses the IAPD registration row. Other checks use the findings the page lists.
-- Does not call lab_live_counts(true). Stored pills and the current score stay until that call.
-- Non-lab firms still read the stored pill. Nothing is dropped.

create table if not exists public.live_count_backup (
  id bigserial primary key,
  firm_id uuid not null,
  kind text not null check (kind in ('pill', 'score')),
  item_key text not null,
  row_data jsonb not null,
  keep_until timestamptz not null default (now() + interval '3 days'),
  created_at timestamptz not null default now()
);
alter table public.live_count_backup enable row level security;
revoke all on public.live_count_backup from public, anon, authenticated;
comment on table public.live_count_backup is
  'Lab stored pills and current scores, kept 3 days. Not deleted without Alex''s OK.';

create or replace function public._lab_live_pill(p_firm uuid, p_n int)
returns table(state text, count_label text, why text)
language plpgsql stable security definer set search_path = public as $$
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

  if sub is not null then
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
    if fin > 0 then
      select count(*)::int into hot from check_findings(sub) c
       where c.k = 6 and coalesce(c.status, '') ~* 'active|open|pending|ongoing'
         and coalesce(c.status, '') !~* '^(dismissed|closed|settled|withdrawn)';
    else
      select count(*)::int into hot from check_saved_items(p_firm, 6) c
       where coalesce(c.status, '') ~* 'active|open|pending|ongoing'
         and coalesce(c.status, '') !~* '^(dismissed|closed|settled|withdrawn)';
    end if;
    if hot > 0 then
      v_state := 'review'; v_why := 'a finding is active, open, or pending';
    else
      v_state := 'wk'; v_why := 'findings are closed cases';
    end if;
    if hot > 0 and hot = items then
      v_count := case when items = 1 then '1 active case' else items::text || ' active cases' end;
    else
      v_count := case when items = 1 then '1 case' else items::text || ' cases' end;
    end if;
  elsif items > 0 and p_n = 4 then
    v_state := 'review';
    if fin > 0 then
      select count(*)::int into hot from check_findings(sub) c
       where c.k = 4 and coalesce(c.status, '') ~* 'open|probe'
         and coalesce(c.status, '') !~* 'settled|closed';
    else
      select count(*)::int into hot from check_saved_items(p_firm, 4) c
       where coalesce(c.status, '') ~* 'open|probe'
         and coalesce(c.status, '') !~* 'settled|closed';
    end if;
    if hot > 0 then
      v_count := case when hot = 1 then '1 open probe' else hot::text || ' open probes' end;
      v_why := 'open regulator findings';
    else
      v_count := case when items = 1 then '1 action' else items::text || ' actions' end;
      v_why := 'regulator findings';
    end if;
  elsif items > 0 and p_n = 10 then
    v_state := 'wk';
    v_count := case when items = 1 then '1 record' else items::text || ' records' end;
    v_why := 'political-tie findings';
  elsif items > 0 and p_n = 9 then
    v_state := 'review';
    v_count := case when items = 1 then '1 finding' else items::text || ' findings' end;
    v_why := 'people-screen findings';
  elsif items > 0 and p_n = 7 then
    v_state := 'clear';
    v_count := case when items = 1 then '1 non-party mention' else items::text || ' non-party mentions' end;
    v_why := 'non-US findings';
  elsif items > 0 then
    v_state := 'review';
    v_count := case when items = 1 then '1 record' else items::text || ' records' end;
    v_why := 'findings on this check';
  elsif looked then
    v_state := case when p_n = 10 then 'nf' else 'clear' end;
    v_count := null;
    v_why := 'searched, no findings';
  else
    v_state := 'nc';
    v_count := null;
    v_why := 'no findings and this check was not searched';
  end if;

  if v_state = stored_st and stored_cnt is not null and v_count is not null
     and (select count(*) from regexp_matches(stored_cnt, '\d+', 'g')) = 1
     and (regexp_match(stored_cnt, '\d+'))[1] = (regexp_match(v_count, '\d+'))[1]
  then
    v_count := stored_cnt;
  end if;

  return query select v_state, v_count, v_why;
end $$;
revoke all on function public._lab_live_pill(uuid, int) from public, anon, authenticated;

create or replace function public._firm_checks_done(p_firm uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from firm_check_rows r
  where r.firm_id = p_firm
    and (case when public._lab_firm(p_firm)
              then (select p.state from public._lab_live_pill(p_firm, r.n) p)
              else r.state end) <> 'nc' $$;
revoke all on function public._firm_checks_done(uuid) from public, anon, authenticated;

create or replace function public.my_firms()
returns json language sql stable security definer set search_path to 'public' as $$
  with ch as (select ce.firm_id, min(ce.created_at) at from check_events ce join check_balances b on b.id = ce.balance_id
              where b.user_id = auth.uid() and ce.kind like 'spend_%' and ce.firm_id is not null group by ce.firm_id),
       sv as (select firm_id, created_at at from watchlist where profile_id = auth.uid()),
       ids as (select firm_id from ch union select firm_id from sv)
  select coalesce(json_agg(json_build_object('slug', f.slug, 'name', f.name, 'short_name', f.short_name, 'hq', f.hq,
    'checked_at', ch.at, 'saved', sv.at is not null, 'saved_at', sv.at,
    'clear', r.clear, 'review', r.review, 'wk', r.wk) order by greatest(ch.at, sv.at) desc), '[]'::json)
  from ids join firms f on f.id = ids.firm_id
  left join ch on ch.firm_id = f.id left join sv on sv.firm_id = f.id
  cross join lateral (
    select count(*) filter (where st in ('clear', 'nf')) clear,
           count(*) filter (where st in ('review', 'red')) review,
           count(*) filter (where st = 'wk') wk
    from (
      select case when public._lab_firm(f.id)
                  then (select p.state from public._lab_live_pill(f.id, n) p)
                  else state end st
      from firm_check_rows where firm_id = f.id
    ) s
  ) r
  where auth.uid() is not null
$$;
revoke all on function public.my_firms() from public, anon;
grant execute on function public.my_firms() to authenticated;

-- Dry run lists page pills and My firms tallies that would change. p_write backs up, then
-- clears the stored count text and the current score for lab firms only. State stays in the
-- column because it cannot be null; the lab page does not read it.
create or replace function public.lab_live_counts(p_write boolean default false)
returns table(slug text, item text, shown text, live text, why text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare r record;
begin
  create temp table if not exists live_diff (
    slug text, item text, shown text, live text, why text
  ) on commit drop;
  truncate live_diff;

  insert into live_diff(slug, item, shown, live, why)
  select f.slug, 'check ' || g.n::text,
         g.state || coalesce(' · ' || g.count_label, ''),
         p.state || coalesce(' · ' || p.count_label, ''),
         p.why
  from firms f
  join firm_check_rows g on g.firm_id = f.id
  cross join lateral public._lab_live_pill(f.id, g.n) p
  where public._lab_firm(f.id)
    and (g.state is distinct from p.state or g.count_label is distinct from p.count_label);

  insert into live_diff(slug, item, shown, live, why)
  select f.slug, 'my firms',
         'clear ' || c.clear::text || ', review ' || c.review::text || ', worth knowing ' || c.wk::text,
         'clear ' || n.clear::text || ', review ' || n.review::text || ', worth knowing ' || n.wk::text,
         'tallies follow the live pills'
  from firms f
  cross join lateral (
    select count(*) filter (where state in ('clear', 'nf')) clear,
           count(*) filter (where state in ('review', 'red')) review,
           count(*) filter (where state = 'wk') wk
    from firm_check_rows where firm_id = f.id
  ) c
  cross join lateral (
    select count(*) filter (where st in ('clear', 'nf')) clear,
           count(*) filter (where st in ('review', 'red')) review,
           count(*) filter (where st = 'wk') wk
    from (
      select (select p.state from public._lab_live_pill(f.id, n) p) st from firm_check_rows where firm_id = f.id
    ) s
  ) n
  where public._lab_firm(f.id)
    and (c.clear is distinct from n.clear or c.review is distinct from n.review or c.wk is distinct from n.wk);

  if p_write then
    insert into live_count_backup(firm_id, kind, item_key, row_data)
    select g.firm_id, 'pill', g.n::text, to_jsonb(g)
    from firm_check_rows g
    where public._lab_firm(g.firm_id);
    insert into live_count_backup(firm_id, kind, item_key, row_data)
    select s.firm_id, 'score', s.id::text, to_jsonb(s)
    from score_results s
    where s.is_current and public._lab_firm(s.firm_id);
    update firm_check_rows g set count_label = null where public._lab_firm(g.firm_id);
    update score_results s set is_current = false, updated_at = now()
     where s.is_current and public._lab_firm(s.firm_id);
  end if;

  return query select d.slug, d.item, d.shown, d.live, d.why from live_diff d order by d.slug, d.item;
end $$;
revoke all on function public.lab_live_counts(boolean) from public, anon, authenticated;

-- Lab firms read the live pill. Section counts and activity stay the queries already in this function.
CREATE OR REPLACE FUNCTION public.firm_page(p_slug text, p_anon uuid, p_spend boolean DEFAULT false, p_email text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
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
    from firm_profile_facts where firm_id = f.id and not hidden and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
  vq := case when public._visitor_checking(q) then 'claimed' when q.status = 'claimed' then 'queued' else q.status end;
  vs := case when public._visitor_checking(q) then q.claimed_at end;
  return json_build_object('status', 'ok', 'open', true, 'unchecked', false, 'done', _firm_checks_done(f.id),
    'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', hq, 'website', web, 'assets', assets),
    'hero', hero, 'sections', secs,
    'checks', (with cf as materialized (select d.s, c.* from (select distinct source_submission as s from firm_check_rows where firm_id = f.id) d
                                          cross join lateral check_findings(d.s) c)
      select json_agg(json_build_object('n', r.n, 'title', r.title, 'descr', r.descr,
        'state', case
          when lp.state is not null and coalesce(cardinality(r.name_only), 0) > 0 and lp.state in ('nc', 'clear', 'nf') then 'clear'
          when lp.state is not null then lp.state
          when coalesce(cardinality(r.name_only), 0) > 0 and r.state in ('nc', 'clear', 'nf') then 'clear'
          else r.state end,
        'count', case when lp.state is not null then lp.count_label else r.count_label end,
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
      left join lateral public._lab_live_pill(r.firm_id, r.n) lp on public._lab_firm(f.id)
      where r.firm_id = f.id),
    'queue', vq, 'started_at', vs,
    'details', u->'details', 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon),
      'activity', public._firm_activity(f.id, open));
end $$;
