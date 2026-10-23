-- Research import (reviewed staging -> company page tables). Importer: tools/ingest/import_research.py.
-- Backup: /workspace/toxybase/backups/2026-10-23-pre-import/ (row counts + md5 per table); git tag pre-research-import.
-- Adds an LP section: firm_profile_facts.section 'lps' (rows copied from firm_lps, each with its source_url as a source chip).
-- Rollback: delete from firm_profile_facts where section = 'lps'; delete from page_sections where key = 'lps';
--   restore the check to ('overview','funds') and _sec_items from 20261022180000_company_page.sql.
alter table public.firm_profile_facts drop constraint if exists firm_profile_facts_section_check;
alter table public.firm_profile_facts add constraint firm_profile_facts_section_check check (section in ('overview', 'funds', 'lps'));
insert into public.page_sections (key, sort_order, title, subtitle, renderer, unit_one, unit_many) values
  ('lps', 75, 'Limited partners', 'Named LP commitments, each with its source.', 'facts', 'LP', 'LPs')
on conflict (key) do update set sort_order = excluded.sort_order, title = excluded.title, subtitle = excluded.subtitle,
  renderer = excluded.renderer, unit_one = excluded.unit_one, unit_many = excluded.unit_many;

CREATE OR REPLACE FUNCTION public._sec_items(p_key text, p_firm uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(it order by o), '[]') from (
    select jsonb_build_object('head', label || ': ' || value, 'label', label, 'value', value, 'src', _src('firm_profile_facts', id)) it, sort_order o
      from firm_profile_facts where firm_id = p_firm and section = p_key and p_key in ('overview', 'funds', 'lps')
    union all
    select jsonb_build_object('head', 'Check ' || n || ': ' || title, 'n', n, 'title', title, 'descr', descr, 'state', state, 'count', count_label, 'src', '[]'::jsonb), n
      from firm_check_rows where firm_id = p_firm and p_key = 'checks'
    union all
    select jsonb_build_object('head', title, 'grp', grp, 'year', year_label, 'role', role, 'state', state, 'status', status_label, 'tone', tone, 'note', note,
        'src', _src('firm_legal_items', id)), case grp when 'case' then 0 when 'regulator' then 1000 else 2000 end + sort_order
      from firm_legal_items where firm_id = p_firm and p_key = 'legal'
    union all
    select jsonb_build_object('head', p.headline, 'outlet', p.publisher, 'date', p.published_label, 'url', p.url, 'snippet', p.snippet, 'logo', p.logo_path, 'group', p.group_label,
        'src', jsonb_build_array(jsonb_build_object('label', p.publisher, 'date', p.published_label, 'url', p.url))), pf.sort_order
      from press_items p join press_item_firms pf on pf.press_item_id = p.id
      where pf.firm_id = p_firm and p_key = 'press' and p.data_status = 'real' and p.url <> ''
    union all
    select jsonb_build_object('head', headline, 'outlet', outlet, 'date', date_label, 'url', url, 'snippet', snippet, 'src', _src('founder_accounts', id)), sort_order
      from founder_accounts where firm_id = p_firm and p_key = 'founders'
    union all
    select jsonb_build_object('head', person_name, 'kind', kind, 'role', role, 'badge', badge, 'src', _src('firm_people_roles', id)),
        case kind when 'board' then 0 when 'move' then 1000 else 2000 end + sort_order
      from firm_people_roles where firm_id = p_firm and p_key = 'people'
    union all
    select jsonb_build_object('head', date_label || ' · ' || body, 'date', date_label, 'kind', kind, 'body', body, 'src', _src('timeline_events', id)), sort_order
      from timeline_events where firm_id = p_firm and p_key = 'timeline'
  ) x where p_key in ('checks', 'press') or jsonb_array_length(it->'src') > 0
$function$;
revoke all on function public._sec_items(text, uuid) from public, anon, authenticated;
