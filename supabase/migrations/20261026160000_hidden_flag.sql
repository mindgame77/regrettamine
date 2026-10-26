-- Step 3: a hidden flag (with reason) on overview facts, legal items, timeline and press links.
-- Page data skips hidden rows (data filter only; no layout change). Hiding is restorable.
-- Promote can never unhide a row: a trigger keeps hidden = true unless restore_hidden() is the caller.
--  record_removed(table, row, firm, reason, who, hide => true): records the item, locks it and hides it with the reason.
--  restore_hidden(table, row, firm, who): unhides it and drops its removed-items entry and lock.

alter table public.firm_profile_facts add column if not exists hidden boolean not null default false;
alter table public.firm_legal_items   add column if not exists hidden boolean not null default false;
alter table public.timeline_events    add column if not exists hidden boolean not null default false;
alter table public.press_item_firms   add column if not exists hidden boolean not null default false;
alter table public.firm_profile_facts add column if not exists hidden_reason text, add column if not exists hidden_at timestamptz, add column if not exists hidden_by text;
alter table public.firm_legal_items add column if not exists hidden_reason text, add column if not exists hidden_at timestamptz, add column if not exists hidden_by text;
alter table public.timeline_events add column if not exists hidden_reason text, add column if not exists hidden_at timestamptz, add column if not exists hidden_by text;
alter table public.press_item_firms add column if not exists hidden_reason text, add column if not exists hidden_at timestamptz, add column if not exists hidden_by text;
alter table public.firm_people_roles add column if not exists hidden_reason text, add column if not exists hidden_at timestamptz, add column if not exists hidden_by text;

create or replace function public._keep_hidden() returns trigger language plpgsql set search_path = public as $$
begin
  if old.hidden and not new.hidden and coalesce(current_setting('app.unhide', true), '') <> '1' then
    new.hidden := true; new.hidden_reason := old.hidden_reason; new.hidden_at := old.hidden_at; new.hidden_by := old.hidden_by;
  end if;
  return new;
end $$;
revoke execute on function public._keep_hidden() from public, anon, authenticated;
drop trigger if exists keep_hidden on public.firm_profile_facts;
create trigger keep_hidden before update of hidden on public.firm_profile_facts for each row execute function public._keep_hidden();
drop trigger if exists keep_hidden on public.firm_legal_items;
create trigger keep_hidden before update of hidden on public.firm_legal_items for each row execute function public._keep_hidden();
drop trigger if exists keep_hidden on public.timeline_events;
create trigger keep_hidden before update of hidden on public.timeline_events for each row execute function public._keep_hidden();
drop trigger if exists keep_hidden on public.press_item_firms;
create trigger keep_hidden before update of hidden on public.press_item_firms for each row execute function public._keep_hidden();
drop trigger if exists keep_hidden on public.firm_people_roles;
create trigger keep_hidden before update of hidden on public.firm_people_roles for each row execute function public._keep_hidden();

-- people already hidden by a recorded cleanup get that cleanup's reason
update public.firm_people_roles p set hidden_reason = r.reason, hidden_at = r.removed_at, hidden_by = r.removed_by
  from public.removed_items r
 where r.source_table = 'firm_people_roles' and r.source_row_id = p.id and p.hidden and p.hidden_reason is null;

drop function if exists public.record_removed(text, uuid, uuid, text, text);
create or replace function public.record_removed(p_table text, p_row_id uuid, p_firm uuid, p_reason text, p_who text default 'cleanup', p_hide boolean default false)
 returns bigint language plpgsql security definer set search_path = public as $$
declare r jsonb; urls text[]; rid bigint;
begin
  if coalesce(btrim(p_reason), '') = '' then raise exception 'record_removed: a reason is required'; end if;
  if p_table = 'press_item_firms' then
    select to_jsonb(x) into r from press_item_firms x where x.press_item_id = p_row_id and x.firm_id = p_firm;
  else
    execute format('select to_jsonb(x) from %I x where x.id = $1', p_table) into r using p_row_id;
  end if;
  if r is null then raise exception 'record_removed: % row % not found (record before deleting)', p_table, p_row_id; end if;
  select array_agg(distinct s.url) into urls from fact_sources fs join sources s on s.id = fs.source_id
   where fs.fact_type = p_table and fs.fact_id = p_row_id;
  rid := _removed_add(p_firm, p_table, p_row_id, r, urls, p_reason, p_who);
  insert into locked_rows(table_name, row_id, firm_id, reason) values (p_table, p_row_id, p_firm, 'removed: ' || p_reason) on conflict do nothing;
  if p_hide then
    if p_table = 'press_item_firms' then
      update press_item_firms set hidden = true, hidden_reason = p_reason, hidden_at = now(), hidden_by = p_who
       where press_item_id = p_row_id and firm_id = p_firm;
    elsif p_table in ('firm_profile_facts', 'firm_legal_items', 'timeline_events', 'firm_people_roles') then
      execute format('update %I set hidden = true, hidden_reason = $2, hidden_at = now(), hidden_by = $3 where id = $1', p_table)
        using p_row_id, p_reason, p_who;
    else raise exception 'record_removed: % has no hidden flag', p_table;
    end if;
  end if;
  return rid;
end $$;

create or replace function public.restore_hidden(p_table text, p_row_id uuid, p_firm uuid, p_who text default 'restore')
 returns boolean language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_table not in ('firm_profile_facts', 'firm_legal_items', 'timeline_events', 'press_item_firms', 'firm_people_roles') then
    raise exception 'restore_hidden: unsupported table %', p_table;
  end if;
  perform set_config('app.unhide', '1', true);
  if p_table = 'press_item_firms' then
    update press_item_firms set hidden = false, hidden_reason = null, hidden_at = now(), hidden_by = p_who
     where press_item_id = p_row_id and firm_id = p_firm and hidden;
  else
    execute format('update %I set hidden = false, hidden_reason = null, hidden_at = now(), hidden_by = $3 where id = $1 and firm_id = $2 and hidden', p_table)
      using p_row_id, p_firm, p_who;
  end if;
  get diagnostics n = row_count;
  perform set_config('app.unhide', '', true);
  if n > 0 then
    delete from removed_items where source_table = p_table and source_row_id = p_row_id and firm_id = p_firm;
    delete from locked_rows where table_name = p_table and row_id = p_row_id and firm_id = p_firm and reason like 'removed: %';
  end if;
  return n > 0;
end $$;

revoke execute on function public.record_removed(text, uuid, uuid, text, text, boolean), public.restore_hidden(text, uuid, uuid, text)
  from public, anon, authenticated;

-- page data skips hidden rows
CREATE OR REPLACE FUNCTION public._sec_items(p_key text, p_firm uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(it order by o), '[]') from (
    select jsonb_build_object('head', label || ': ' || v, 'label', label, 'value', v, 'src', _src('firm_profile_facts', id) || _ovr_src('firm_profile_facts', id)) it, sort_order o
      from (select *, coalesce(_ovr('firm_profile_facts', id, 'value'), value) v from firm_profile_facts where firm_id = p_firm and not hidden and section = p_key and p_key in ('overview', 'funds', 'lps')) ff
    union all
    select jsonb_build_object('head', 'Check ' || n || ': ' || title, 'n', n, 'title', title, 'descr', descr, 'state', state, 'count', count_label, 'src', '[]'::jsonb), n
      from firm_check_rows where firm_id = p_firm and p_key = 'checks'
    union all
    select jsonb_build_object('head', title, 'grp', grp, 'year', year_label, 'role', role, 'state', state, 'status', status_label, 'tone', tone, 'note', coalesce(_ovr('firm_legal_items', id, 'note'), note),
        'src', _src('firm_legal_items', id) || _ovr_src('firm_legal_items', id)), case grp when 'case' then 0 when 'regulator' then 1000 else 2000 end + sort_order
      from firm_legal_items where firm_id = p_firm and not hidden and p_key = 'legal'
    union all
    select jsonb_build_object('head', p.headline, 'outlet', source_label(p.publisher, p.url) || case when _own_media(p_firm, p.url) then ' · Own media' else '' end, 'independent', not _own_media(p_firm, p.url), 'date', p.published_label, 'url', p.url, 'snippet', p.snippet, 'logo', p.logo_path, 'group', p.group_label,
        'src', jsonb_build_array(jsonb_build_object('label', source_label(p.publisher, p.url), 'date', p.published_label, 'url', p.url))), pf.sort_order
      from press_items p join press_item_firms pf on pf.press_item_id = p.id
      where pf.firm_id = p_firm and not pf.hidden and p_key = 'press' and p.data_status = 'real' and p.url <> ''
    union all
    select jsonb_build_object('head', headline, 'outlet', regexp_replace(outlet, ' · firm-owned, not independent$', '') || case when ind then '' else ' · Own media' end, 'independent', ind, 'date', date_label, 'url', url, 'snippet', snippet, 'src', _src('founder_accounts', id)), sort_order
      from (select *, independent and not _own_media(p_firm, url) ind from founder_accounts where firm_id = p_firm and p_key = 'founders' and moved_to_review is null and moved_to is null) fa
    union all
    select jsonb_build_object('head', person_name, 'kind', kind, 'role', coalesce(_ovr('firm_people_roles', id, 'role'), role),
        'badge', case when _ovr('firm_people_roles', id, 'role') is not null then 'Corrected' else badge end,
        'src', _src('firm_people_roles', id) || _ovr_src('firm_people_roles', id)),
        case kind when 'board' then 0 when 'move' then 1000 else 2000 end + sort_order
      from firm_people_roles where firm_id = p_firm and p_key = 'people' and not hidden
    union all
    select jsonb_build_object('head', date_label || ' · ' || body, 'date', date_label, 'kind', kind, 'body', body, 'src', _src('timeline_events', id)), sort_order
      from timeline_events where firm_id = p_firm and not hidden and p_key = 'timeline'
  ) x where p_key in ('checks', 'press') or jsonb_array_length(it->'src') > 0
$function$;

CREATE OR REPLACE FUNCTION public.firm_page(p_slug text, p_anon uuid, p_spend boolean DEFAULT false, p_email text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        'state', case when coalesce(cardinality(r.name_only), 0) > 0 and r.state in ('nc', 'clear', 'nf') then 'clear' else r.state end,
        'count', r.count_label,
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
      where r.firm_id = f.id),
    'queue', vq, 'started_at', vs,
    'details', u->'details', 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon),
      'activity', public._firm_activity(f.id, open));
end $function$;

CREATE OR REPLACE FUNCTION public.published_site_core()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with pub as (
    select id from firms where published and indexable and not is_test
  ),
  pub_matters as (
    select distinct matter_id as id from legal_matter_firms where firm_id in (select id from pub)
  ),
  pub_cards as (
    select id from evidence_cards where firm_id in (select id from pub)
  ),
  pub_sources as (
    select distinct source_id as id from fact_sources where firm_id in (select id from pub)
  ),
  pub_people as (
    select person_id as id from fund_people where firm_id in (select id from pub)
    union
    select founder_person_id from reviews where firm_id in (select id from pub) and founder_person_id is not null
    union
    select partner_person_id from reviews where firm_id in (select id from pub) and partner_person_id is not null
    union
    select board_person_id from investments where firm_id in (select id from pub) and board_person_id is not null
    union
    select cf.person_id from company_founders cf join investments i on i.company_id = cf.company_id where i.firm_id in (select id from pub)
  ),
  pub_companies as (
    select distinct company_id as id from investments where firm_id in (select id from pub)
  ),
  pub_press as (
    select press_item_id as id from press_item_firms where firm_id in (select id from pub) and not hidden
  ),
  pub_results as (
    select id from score_results where firm_id in (select id from pub)
  ),
  pub_reviews as (
    select id from reviews where firm_id in (select id from pub)
  )
  select jsonb_build_object(
    'firms', coalesce((select jsonb_agg(to_jsonb(t) order by t.list_sort, t.slug) from firms t where t.id in (select id from pub)), '[]'::jsonb),
    'funds', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order, t.name) from funds t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'fund_entities', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from fund_entities t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'people', coalesce((select jsonb_agg(to_jsonb(t) order by t.full_name) from people t where t.id in (select id from pub_people)), '[]'::jsonb),
    'fund_people', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from fund_people t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'portfolio_companies', coalesce((select jsonb_agg(to_jsonb(t) order by t.name) from portfolio_companies t where t.id in (select id from pub_companies)), '[]'::jsonb),
    'company_founders', coalesce((select jsonb_agg(to_jsonb(t)) from company_founders t where t.company_id in (select id from pub_companies)), '[]'::jsonb),
    'investments', coalesce((select jsonb_agg(to_jsonb(t)) from investments t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'reviews', coalesce((
      select jsonb_agg(to_jsonb(t) order by t.reviewed_on nulls last, t.created_at)
      from (
        select
          id, firm_id, fund_id, company_id, founder_person_id, partner_person_id,
          body, first_hand, verification_status, moderation_status, reviewed_on,
          created_at, updated_at, profile_id, anonymous, role_label, round_label,
          would_again, verification_method, connection_type,
          honesty, support_after_check, founder_friendly_terms, responsiveness, hard_times
        from reviews
        where firm_id in (select id from pub)
      ) t
    ), '[]'::jsonb),
    'review_ratings', coalesce((select jsonb_agg(to_jsonb(t)) from review_ratings t where t.review_id in (select id from pub_reviews)), '[]'::jsonb),
    'legal_matters', coalesce((select jsonb_agg(to_jsonb(t)) from legal_matters t where t.id in (select id from pub_matters)), '[]'::jsonb),
    'legal_matter_firms', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from legal_matter_firms t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'legal_matter_parties', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from legal_matter_parties t where t.matter_id in (select id from pub_matters)), '[]'::jsonb),
    'filings', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from filings t where t.matter_id in (select id from pub_matters)), '[]'::jsonb),
    'docket_entries', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from docket_entries t where t.matter_id in (select id from pub_matters)), '[]'::jsonb),
    'legal_groups', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from legal_groups t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'legal_group_items', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from legal_group_items t where t.group_id in (select id from legal_groups where firm_id in (select id from pub))), '[]'::jsonb),
    'regulatory_records', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from regulatory_records t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'sanctions_checks', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from sanctions_checks t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'press_items', coalesce((select jsonb_agg(to_jsonb(t)) from press_items t where t.id in (select id from pub_press)), '[]'::jsonb),
    'press_item_firms', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from press_item_firms t where t.firm_id in (select id from pub) and not t.hidden), '[]'::jsonb),
    'sources', coalesce((select jsonb_agg(to_jsonb(t)) from sources t where t.id in (select id from pub_sources)), '[]'::jsonb),
    'fact_sources', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from fact_sources t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'takeaways', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from takeaways t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'ask_questions', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from ask_questions t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'copy_blocks', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from copy_blocks t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'page_chips', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from page_chips t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'firm_meta_items', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from firm_meta_items t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'list_items', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from list_items t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'portfolio_metrics', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from portfolio_metrics t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'firm_ranks', coalesce((select jsonb_agg(to_jsonb(t)) from firm_ranks t where t.firm_id in (select id from pub) and t.is_current), '[]'::jsonb),
    'evidence_cards', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from evidence_cards t where t.firm_id in (select id from pub)), '[]'::jsonb),
    'evidence_lines', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from evidence_lines t where t.card_id in (select id from pub_cards)), '[]'::jsonb),
    'score_versions', coalesce((select jsonb_agg(to_jsonb(t)) from score_versions t), '[]'::jsonb),
    'score_sections', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from score_sections t), '[]'::jsonb),
    'score_results', coalesce((select jsonb_agg(to_jsonb(t)) from score_results t where t.id in (select id from pub_results)), '[]'::jsonb),
    'score_result_parts', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from score_result_parts t where t.result_id in (select id from pub_results)), '[]'::jsonb),
    'score_lines', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from score_lines t where t.result_id in (select id from pub_results)), '[]'::jsonb),
    'score_inputs', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from score_inputs t where t.result_id in (select id from pub_results)), '[]'::jsonb),
    'site_stats', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from site_stats t), '[]'::jsonb),
    'site_updates', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from site_updates t), '[]'::jsonb)
  );
$function$;

CREATE OR REPLACE FUNCTION public._firm_assets(p_firm uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    (select (regexp_match(f.value, '\$[0-9][0-9,]*\.[0-9]+|\$[0-9][0-9,]*'))[1]
       from firm_profile_facts f
      where f.firm_id = p_firm and not f.hidden
        and f.value ~* '(item[[:space:]]*5[[:space:]]*f|regulatory[[:space:]]+aum|regulatory[[:space:]]+assets)'
        and f.value !~* 'schedule[[:space:]]*d|gross[[:space:]]+asset'
        and f.value ~ '\$[0-9]'
      order by case when f.value ~* 'item[[:space:]]*5[[:space:]]*f' then 0 else 1 end, f.sort_order
      limit 1),
    (select fi.aum_display from firms fi where fi.id = p_firm and fi.aum_display ~ '^\$')
  );
$function$;

CREATE OR REPLACE FUNCTION public._firm_website(p_firm uuid, p_domain text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with raw as (
    select 0 as pri, case when btrim(p_domain) ~* '^https?://' then btrim(p_domain) else 'https://' || btrim(p_domain) end as url
      where nullif(btrim(p_domain), '') is not null
    union all
    select 1, s.url from fact_sources fs join sources s on s.id = fs.source_id
      where fs.firm_id = p_firm and s.url ~* '^https?://'
    union all
    select 2, m[1] from firm_profile_facts f
      cross join lateral regexp_matches(coalesce(f.value, ''), $re$https?://[^[:space:]<>"')]+$re$, 'gi') as m
      where f.firm_id = p_firm and not f.hidden
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
        where f.firm_id = p_firm and not f.hidden and position(o.host in lower(f.value)) > 0
     ) then 0 else 1 end,
     o.pri
   limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.check_saved_items(p_firm uuid, p_n integer)
 RETURNS TABLE(k integer, title text, yr text, status text, note text, who text, court text, src_url text, src_label text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
   where li.firm_id = p_firm and not li.hidden
     and (
       (p_n in (6, 7) and li.grp = 'case' and li.state = 'Active'
         and coalesce(public._ck_non_us(jsonb_build_object('value', jsonb_build_object('court', li.note, 'jurisdiction', ''))), false) = (p_n = 7))
       or (p_n = 4 and li.grp = 'regulator'
         and coalesce(li.status_label, '') !~* '^(none|no match|needs proof|worth knowing|parent)'
         and coalesce(li.status_label, '') ~* 'open|probe|pending|settled|order')
     );
$function$;
