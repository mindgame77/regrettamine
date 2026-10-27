-- Rollback for 20261027221000_timeline_check_mark.sql and 20261027221100_news_one_list_data.sql.
-- Not applied by scripts/migrate.py. Does not delete timeline rows.
-- Deletes only the press copy this change inserted (source_system vc_source_facts-copy).
-- Does not delete or update vc_source_facts.

delete from public.press_item_firms pf
using public.press_items p
where p.id = pf.press_item_id
  and p.source_system = 'vc_source_facts-copy'
  and p.external_id = '734e8c24-7781-5169-8f93-2aa79085dc54';

delete from public.press_items
where source_system = 'vc_source_facts-copy'
  and external_id = '734e8c24-7781-5169-8f93-2aa79085dc54';

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
      where pf.firm_id = p_firm and pf.check_mark = 'checked_correct' and p_key = 'press' and p.url <> ''
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

alter table public.timeline_events
  drop constraint if exists timeline_events_check_mark_chk;
alter table public.timeline_events
  drop column if exists check_note,
  drop column if exists check_mark,
  drop column if exists source_url;
