-- Press check mark. Proposed, not applied. Do not run this until Alex accepts the mapping.
--
-- Press has no verified boolean. A firm page shows an article today when
-- press_items.data_status = 'real', press_item_firms.hidden = false, and the url is not empty.
-- The only check evidence on the link is last_checked_at (and checked_source).
-- Measured 2026-10-27 against the live database, before this migration:
--   293 links, all data_status real, all hidden = false, all urls present, all last_checked_at null,
--   all checked_source null. 114 of those links are on the 135 pilot firms (33 of those firms).
--   62 press_items have no firm link, so they are not on a page and get no mark.
--
-- Mapping (applied by the update below, so a later last_checked_at is respected at apply time):
--   checked_correct  when data_status = 'real' AND hidden = false AND url <> '' AND last_checked_at is not null
--   not_checked      every other existing link
--   checked_wrong    not assigned from old rows. A null check is not a rejection, and no link is hidden.
-- On the measured rows that update sets checked_correct 0, checked_wrong 0, not_checked 293
-- (114 not_checked on the pilot firms). Pages that read the mark then show 0 press articles.
--
-- data_status and hidden stay. New inserts leave check_mark to its default, not_checked.
-- A publish is not a check. Hiding a checked_correct link stores checked_wrong; restoring that
-- link stores checked_correct again. Hiding a not_checked link leaves the mark.
--
-- Rollback, if this was applied and should be undone:
--   1. Put the press filters back: _sec_items uses "not pf.hidden and p.data_status = 'real' and p.url <> ''";
--      _section_counts_now counts "not hidden"; published_site_core and data_rules_report use "not hidden".
--   2. Drop trigger press_check_on_hide and function public._press_check_on_hide().
--   3. update section_counts set n = (select count(*) from press_item_firms pf
--        where pf.firm_id = section_counts.firm_id and not pf.hidden), counted_at = now()
--      where section = 'press';
--   4. alter table public.press_item_firms drop column check_mark;
-- Rows are not deleted. data_status and hidden are unchanged by this file.

alter table public.press_item_firms
  add column check_mark text not null default 'not_checked'
  constraint press_item_firms_check_mark_chk
  check (check_mark in ('checked_correct', 'checked_wrong', 'not_checked'));

comment on column public.press_item_firms.check_mark is
  'checked_correct is shown. checked_wrong is a rejected check, kept and hidden. not_checked is hidden. data_status and hidden stay as the backup.';

update public.press_item_firms pf
set check_mark = 'checked_correct'
from public.press_items p
where p.id = pf.press_item_id
  and p.data_status = 'real'
  and not pf.hidden
  and coalesce(p.url, '') <> ''
  and pf.last_checked_at is not null;

-- Firm pages. Other sections are unchanged.
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
    select press_item_id as id from press_item_firms where firm_id in (select id from pub) and check_mark = 'checked_correct'
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
    'press_item_firms', coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from press_item_firms t where t.firm_id in (select id from pub) and t.check_mark = 'checked_correct'), '[]'::jsonb),
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

create or replace function public.data_rules_report()
 returns table(firm_id uuid, slug text, rule text, tbl text, row_id uuid, reason text)
 language sql stable security definer set search_path = public as $$
  with src as (
    select fs.fact_type, fs.fact_id, min(s.url) filter (where s.url ~* '^https?://') url
      from fact_sources fs join sources s on s.id = fs.source_id group by 1, 2
  ),
  rows as (
    select x.firm_id, 'firm_profile_facts' tbl, x.id, x.section sec, case when x.label ~* '^lead' then 'lead' else 'live' end knd,
           jsonb_build_object('label', x.label, 'value', x.value) f, src.url
      from firm_profile_facts x left join src on src.fact_type = 'firm_profile_facts' and src.fact_id = x.id where not x.hidden
    union all
    select x.firm_id, 'firm_legal_items', x.id, 'legal', 'live',
           jsonb_build_object('title', x.title, 'status', x.status_label, 'allegation', coalesce(x.tone, '') ~* '(lead|allegation)'), src.url
      from firm_legal_items x left join src on src.fact_type = 'firm_legal_items' and src.fact_id = x.id where not x.hidden
    union all
    select x.firm_id, 'timeline_events', x.id, 'timeline', 'live', jsonb_build_object('date', x.date_label, 'event', x.body), src.url
      from timeline_events x left join src on src.fact_type = 'timeline_events' and src.fact_id = x.id where not x.hidden
    union all
    select x.firm_id, 'firm_people_roles', x.id, 'people', case when coalesce(x.badge, '') ~* 'lead' then 'lead' else 'live' end,
           jsonb_build_object('name', x.person_name, 'role', x.role), src.url
      from firm_people_roles x left join src on src.fact_type = 'firm_people_roles' and src.fact_id = x.id where not x.hidden
    union all
    select pf.firm_id, 'press_item_firms', pf.press_item_id, 'press', 'live',
           jsonb_build_object('headline', p.headline, 'date', p.published_on::text), p.url
      from press_item_firms pf join press_items p on p.id = pf.press_item_id where pf.check_mark = 'checked_correct'
  ),
  checked as (
    select r.*, _data_rule(r.sec, r.knd, r.f, r.url) why from rows r
  ),
  dupes as (
    select firm_id, tbl, id, 'duplicate: same as another row on this page' why from (
      select firm_id, tbl, id, row_number() over (partition by firm_id, tbl, k order by id) rn from (
        select firm_id, 'firm_profile_facts' tbl, id, section || '|' || lower(label) || '|' || _norm_txt(value) k from firm_profile_facts where not hidden
        union all select firm_id, 'firm_legal_items', id, _norm_txt(title) from firm_legal_items where not hidden
        union all select firm_id, 'timeline_events', id, date_label || '|' || _norm_txt(body) from timeline_events where not hidden
        union all select firm_id, 'firm_people_roles', id, kind || '|' || _norm_txt(person_name) || '|' || _norm_txt(role) from firm_people_roles where not hidden
      ) k) z where rn > 1
  )
  select c.firm_id, f.slug, split_part(c.why, ':', 1), c.tbl, c.id, c.why from checked c join firms f on f.id = c.firm_id where c.why is not null
  union all
  select d.firm_id, f.slug, 'duplicate', d.tbl, d.id, d.why from dupes d join firms f on f.id = d.firm_id
$$;

revoke execute on function public.data_rules_report() from public, anon, authenticated;

-- Drop detector for press follows the page: only checked_correct counts.
create or replace function public._section_counts_now(p_firm uuid) returns table(section text, n int)
 language sql stable set search_path = public as $$
  select s, coalesce(c, 0)::int from unnest(array['overview', 'funds', 'lps', 'legal', 'timeline', 'people', 'press']) s
  left join (
    select x.section s2, count(*) c from firm_profile_facts x where x.firm_id = p_firm and not x.hidden group by 1
    union all select 'legal', count(*) from firm_legal_items where firm_id = p_firm and not hidden
    union all select 'timeline', count(*) from timeline_events where firm_id = p_firm and not hidden
    union all select 'people', count(*) from firm_people_roles where firm_id = p_firm and not hidden
    union all select 'press', count(*) from press_item_firms where firm_id = p_firm and check_mark = 'checked_correct'
  ) q on q.s2 = s $$;
revoke execute on function public._section_counts_now(uuid) from public, anon, authenticated;

-- A deliberate hide of a shown article is the rejected-check state. Runs after keep_hidden
-- (trigger names sort keep_hidden, then press_check_on_hide).
create or replace function public._press_check_on_hide() returns trigger
 language plpgsql set search_path = public as $$
begin
  if new.hidden and not old.hidden and old.check_mark = 'checked_correct' then
    new.check_mark := 'checked_wrong';
  elsif not new.hidden and old.hidden and old.check_mark = 'checked_wrong'
        and coalesce(current_setting('app.unhide', true), '') = '1' then
    new.check_mark := 'checked_correct';
  end if;
  return new;
end $$;
revoke execute on function public._press_check_on_hide() from public, anon, authenticated;
drop trigger if exists press_check_on_hide on public.press_item_firms;
create trigger press_check_on_hide before update of hidden on public.press_item_firms
  for each row execute function public._press_check_on_hide();

-- Match the stored press count to the new page rule so the next publish does not
-- raise a drop alert for this proposed change.
update public.section_counts sc
set n = (
  select count(*)::int from public.press_item_firms pf
  where pf.firm_id = sc.firm_id and pf.check_mark = 'checked_correct'
), counted_at = now()
where sc.section = 'press';
