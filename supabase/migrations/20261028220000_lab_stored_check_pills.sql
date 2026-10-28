-- Lab firms: store each firm's 10 check pills/counts/items (the 'checks' block of firm_page) and
-- recompute them only when data behind them is published or changed. firm_page reads the stored
-- block. Non-lab firms, and a lab firm with no stored row, still compute live as before.
-- Rollback: supabase/rollbacks/20261028220000_lab_stored_check_pills.sql

create table if not exists public.firm_check_pills (
  firm_id uuid primary key references public.firms(id) on delete cascade,
  checks json,
  computed_at timestamptz not null default now()
);
alter table public.firm_check_pills enable row level security;
revoke all on public.firm_check_pills from anon, authenticated;

create table if not exists public.firm_check_pills_dirty (firm_id uuid primary key);
alter table public.firm_check_pills_dirty enable row level security;
revoke all on public.firm_check_pills_dirty from anon, authenticated;

-- The live computation, moved out of firm_page unchanged (f.id -> p_firm, f.report_date -> v_report).
create or replace function public._firm_checks_compute(p_firm uuid)
returns json language plpgsql stable security definer set search_path to 'public' as $function$
#variable_conflict use_column
declare v_report date;
begin
  select report_date into v_report from firms where id = p_firm;
  return (with cf as materialized (select d.s, c.* from (select distinct source_submission as s from firm_check_rows where firm_id = p_firm) d cross join lateral check_findings(d.s) c)
      select json_agg(json_build_object('n', r.n, 'title', r.title, 'descr', r.descr,
        'state', case when lp.state is not null and coalesce(cardinality(r.name_only), 0) > 0 and lp.state in ('nc', 'clear', 'nf') then 'clear' when lp.state is not null then lp.state when coalesce(cardinality(r.name_only), 0) > 0 and r.state in ('nc', 'clear', 'nf') then 'clear' else r.state end,
        'count', case when lp.state is not null then lp.count_label else r.count_label end,
        'searched_at', coalesce(r.searched_at, case when r.state <> 'nc' and v_report is not null then (v_report + time '12:00') at time zone 'America/Los_Angeles' end),
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
             else 0 end) lp on public._lab_firm(p_firm)
      where r.firm_id = p_firm);
end $function$;

create or replace function public._firm_checks(p_firm uuid)
returns json language plpgsql stable security definer set search_path to 'public' as $function$
declare c json; hit boolean := false;
begin
  if public._lab_firm(p_firm) then
    select true, checks into hit, c from firm_check_pills where firm_id = p_firm;
  end if;
  if hit then return c; end if;
  return public._firm_checks_compute(p_firm);
end $function$;

create or replace function public.refresh_firm_check_pills(p_firm uuid)
returns void language plpgsql volatile security definer set search_path to 'public' as $function$
begin
  if p_firm is null or not public._lab_firm(p_firm) then return; end if;
  insert into firm_check_pills (firm_id, checks, computed_at)
  values (p_firm, public._firm_checks_compute(p_firm), now())
  on conflict (firm_id) do update set checks = excluded.checks, computed_at = excluded.computed_at;
end $function$;
revoke all on function public.refresh_firm_check_pills(uuid) from public, anon, authenticated;

-- Row triggers only mark the firm dirty; one statement trigger per statement recomputes each dirty firm once.
create or replace function public._pills_mark() returns trigger language plpgsql security definer set search_path to 'bots', 'public' as $function$
declare r record; ids uuid[] := '{}';
begin
  if tg_table_name in ('firm_check_rows', 'firm_legal_items', 'vc_source_facts', 'firm_profile_facts') then
    if tg_op <> 'INSERT' then ids := ids || (to_jsonb(old)->>'firm_id')::uuid; end if;
    if tg_op <> 'DELETE' then ids := ids || (to_jsonb(new)->>'firm_id')::uuid; end if;
  elsif tg_table_name = 'firms' then
    ids := array[new.id];
  elsif tg_table_name = 'fact_sources' then
    select coalesce(array_agg(distinct x.fid), '{}') into ids from (
      select li.firm_id fid from public.firm_legal_items li
       where li.id in ((to_jsonb(old)->>'fact_id')::uuid, (to_jsonb(new)->>'fact_id')::uuid)
         and coalesce(to_jsonb(new)->>'fact_type', to_jsonb(old)->>'fact_type') = 'firm_legal_items'
      union
      select pf.firm_id from public.firm_profile_facts pf
       where pf.id in ((to_jsonb(old)->>'fact_id')::uuid, (to_jsonb(new)->>'fact_id')::uuid)
         and coalesce(to_jsonb(new)->>'fact_type', to_jsonb(old)->>'fact_type') = 'firm_profile_facts') x;
  elsif tg_table_name = 'research_submissions' then
    select coalesce(array_agg(distinct cr.firm_id), '{}') into ids from public.firm_check_rows cr where cr.source_submission = new.id;
  end if;
  insert into public.firm_check_pills_dirty (firm_id)
    select distinct i from unnest(ids) i where i is not null and public._lab_firm(i)
  on conflict do nothing;
  return null;
end $function$;

create or replace function public._pills_flush() returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare fid uuid;
begin
  for fid in delete from public.firm_check_pills_dirty returning firm_id loop
    perform public.refresh_firm_check_pills(fid);
  end loop;
  return null;
end $function$;

drop trigger if exists zz_pills_mark on public.firm_check_rows;
create trigger zz_pills_mark after insert or update or delete on public.firm_check_rows for each row execute function public._pills_mark();
drop trigger if exists zz_pills_flush on public.firm_check_rows;
create trigger zz_pills_flush after insert or update or delete on public.firm_check_rows for each statement execute function public._pills_flush();

drop trigger if exists zz_pills_mark on public.firm_legal_items;
create trigger zz_pills_mark after insert or update or delete on public.firm_legal_items for each row execute function public._pills_mark();
drop trigger if exists zz_pills_flush on public.firm_legal_items;
create trigger zz_pills_flush after insert or update or delete on public.firm_legal_items for each statement execute function public._pills_flush();

drop trigger if exists zz_pills_mark on public.vc_source_facts;
create trigger zz_pills_mark after insert or update or delete on public.vc_source_facts for each row execute function public._pills_mark();
drop trigger if exists zz_pills_flush on public.vc_source_facts;
create trigger zz_pills_flush after insert or update or delete on public.vc_source_facts for each statement execute function public._pills_flush();

drop trigger if exists zz_pills_mark on public.firm_profile_facts;
create trigger zz_pills_mark after insert or update or delete on public.firm_profile_facts for each row execute function public._pills_mark();
drop trigger if exists zz_pills_flush on public.firm_profile_facts;
create trigger zz_pills_flush after insert or update or delete on public.firm_profile_facts for each statement execute function public._pills_flush();

drop trigger if exists zz_pills_mark on public.fact_sources;
create trigger zz_pills_mark after insert or update or delete on public.fact_sources for each row execute function public._pills_mark();
drop trigger if exists zz_pills_flush on public.fact_sources;
create trigger zz_pills_flush after insert or update or delete on public.fact_sources for each statement execute function public._pills_flush();

drop trigger if exists zz_pills_mark on public.firms;
create trigger zz_pills_mark after update of report_date on public.firms for each row execute function public._pills_mark();
drop trigger if exists zz_pills_flush on public.firms;
create trigger zz_pills_flush after update on public.firms for each statement execute function public._pills_flush();

drop trigger if exists zz_pills_mark on bots.research_submissions;
create trigger zz_pills_mark after update of valid, payload on bots.research_submissions for each row execute function public._pills_mark();
drop trigger if exists zz_pills_flush on bots.research_submissions;
create trigger zz_pills_flush after update on bots.research_submissions for each statement execute function public._pills_flush();

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
    'checks', public._firm_checks(f.id),
    'queue', vq, 'started_at', vs, 'details', u->'details', 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon), 'activity', public._firm_activity(f.id, open));
end $function$;

-- Backfill the 10 lab firms (and any extra lab slugs).
select public.refresh_firm_check_pills(f.id) from public.firms f where public._lab_firm(f.id);
