-- Timeline check mark for News. Proposed, not applied to the live database.
-- Adds source_url, check_mark, and check_note on timeline_events.
-- check_mark mirrors press_item_firms: checked_correct is shown, checked_wrong is kept and not shown,
-- not_checked is the default and is not shown. No timeline row is deleted.
-- firm_page News is still press plus timeline, drawn as one list and sorted by date in the browser.
-- This reader returns only checked_correct timeline rows. Legal is unchanged.
-- A new timeline row stays not_checked until a check sets the mark.
-- Rollback: supabase/rollbacks/20261027221000_timeline_check_mark.sql (not applied by scripts/migrate.py).

alter table public.timeline_events
  add column source_url text,
  add column check_mark text not null default 'not_checked'
    constraint timeline_events_check_mark_chk
    check (check_mark in ('checked_correct', 'checked_wrong', 'not_checked')),
  add column check_note text;

comment on column public.timeline_events.check_mark is
  'checked_correct is shown in News. checked_wrong is a rejected check, kept and not shown. not_checked is not shown. hidden stays as the backup.';
comment on column public.timeline_events.source_url is
  'Public source checked for this event. Empty when the event is not_checked.';
comment on column public.timeline_events.check_note is
  'How the check was made. headline_match means a paywalled or title-only source whose headline matches the event.';

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
    select jsonb_build_object('head', date_label || ' · ' || body, 'date', date_label, 'kind', kind, 'body', body,
        'src', case when coalesce(btrim(source_url), '') <> ''
          then jsonb_build_array(jsonb_build_object(
            'label', source_label(regexp_replace(substring(source_url from 'https?://([^/]+)'), '^www\.', '', 'i'), source_url),
            'date', date_label, 'url', source_url))
          else _src('timeline_events', id) end), sort_order
      from timeline_events where firm_id = p_firm and not hidden and check_mark = 'checked_correct' and p_key = 'timeline'
  ) x where p_key in ('checks', 'press') or jsonb_array_length(it->'src') > 0
$function$;
