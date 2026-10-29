-- Legal case summary (Alex 2026-10-29, approved spec + mockup 12-legal-summary): each legal case can carry a short
-- summary written only from its court/regulator record (or existing case notes), with its date and source link.
--   * firm_legal_items gets summary (<= 300 chars), summary_date, summary_source_url, summary_by (research | friend | enricher).
--   * Longer text is trimmed to 300, never rejected for length. A summary with no source link is rejected (the case stays).
--   * A new summary on an Active case replaces the shown one; the old one goes to firm_legal_summary_history (never deleted).
--   * A case that is not Active and already has a summary is not rewritten.
--   * Writers: research/friend bots through research-ingest + import_research (summary_by research|friend);
--     the Enricher through legal_summary_set (summary_by enricher). The Checker only reviews (legal_summary_review).
--   * _sec_items legal items add summary, summary_date, summary_url for the page.
-- Rollback: supabase/rollbacks/20261029160000_legal_case_summary.sql

alter table public.firm_legal_items
  add column if not exists summary text,
  add column if not exists summary_date date,
  add column if not exists summary_source_url text,
  add column if not exists summary_by text;

alter table public.firm_legal_items
  add constraint firm_legal_items_summary_len check (summary is null or char_length(summary) <= 300),
  add constraint firm_legal_items_summary_src check (summary is null or summary_source_url ~* '^https?://[^\s/]+\.[^\s]+$'),
  add constraint firm_legal_items_summary_by check (summary_by is null or summary_by in ('research', 'friend', 'enricher'));

create table if not exists public.firm_legal_summary_history (
  id bigint generated always as identity primary key,
  legal_item_id uuid not null references public.firm_legal_items(id) on delete cascade,
  summary text not null,
  summary_date date,
  summary_source_url text,
  summary_by text,
  replaced_at timestamptz not null default now()
);
create index if not exists firm_legal_summary_history_item on public.firm_legal_summary_history(legal_item_id);
alter table public.firm_legal_summary_history enable row level security;
revoke all on public.firm_legal_summary_history from public, anon, authenticated;

-- Entry check on every write path (ingest, Enricher, any other): normalize, trim to 300, drop a summary with no
-- source link, keep a closed case's summary, archive a replaced one.
create or replace function public._legal_summary_guard()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if new.summary is not null then
    new.summary := nullif(btrim(regexp_replace(new.summary, '\s+', ' ', 'g')), '');
  end if;
  if new.summary is not null and char_length(new.summary) > 300 then
    new.summary := rtrim(left(new.summary, 300));
  end if;
  if new.summary is not null and coalesce(new.summary_source_url, '') !~* '^https?://[^\s/]+\.[^\s]+$' then
    new.summary := null;  -- no source link: rejected, the case itself is kept
  end if;
  if new.summary is null then
    new.summary_date := null; new.summary_source_url := null; new.summary_by := null;
  else
    new.summary_date := coalesce(new.summary_date, current_date);
  end if;
  if tg_op = 'UPDATE' and old.summary is not null
     and (new.summary is distinct from old.summary or new.summary_source_url is distinct from old.summary_source_url) then
    if coalesce(old.state, '') <> 'Active' or new.summary is null then
      -- closed cases are not rewritten, and a shown summary is never blanked by a write
      new.summary := old.summary; new.summary_date := old.summary_date;
      new.summary_source_url := old.summary_source_url; new.summary_by := old.summary_by;
    else
      insert into firm_legal_summary_history(legal_item_id, summary, summary_date, summary_source_url, summary_by)
      values (old.id, old.summary, old.summary_date, old.summary_source_url, old.summary_by);
    end if;
  end if;
  return new;
end
$function$;

drop trigger if exists firm_legal_items_summary_guard on public.firm_legal_items;
create trigger firm_legal_items_summary_guard
  before insert or update of summary, summary_date, summary_source_url, summary_by on public.firm_legal_items
  for each row execute function public._legal_summary_guard();

-- Enricher path: write or refresh one case's summary. Returns {ok, reason}.
create or replace function public.legal_summary_set(p_item uuid, p_summary text, p_date date, p_url text, p_by text default 'enricher')
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare it firm_legal_items; s text;
begin
  if p_by not in ('research', 'friend', 'enricher') then return jsonb_build_object('ok', false, 'reason', 'unknown writer'); end if;
  if coalesce(p_url, '') !~* '^https?://[^\s/]+\.[^\s]+$' then return jsonb_build_object('ok', false, 'reason', 'no source link'); end if;
  s := nullif(btrim(regexp_replace(coalesce(p_summary, ''), '\s+', ' ', 'g')), '');
  if s is null then return jsonb_build_object('ok', false, 'reason', 'empty summary'); end if;
  select * into it from firm_legal_items where id = p_item;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such case'); end if;
  if it.grp not in ('case', 'regulator') then return jsonb_build_object('ok', false, 'reason', 'not a case'); end if;
  if it.summary is not null and coalesce(it.state, '') <> 'Active' then
    return jsonb_build_object('ok', false, 'reason', 'closed case is not rewritten');
  end if;
  update firm_legal_items set summary = s, summary_date = coalesce(p_date, current_date), summary_source_url = p_url, summary_by = p_by
   where id = p_item;
  return jsonb_build_object('ok', true, 'trimmed', char_length(s) > 300, 'replaced', it.summary is not null);
end
$function$;
revoke all on function public.legal_summary_set(uuid, text, date, text, text) from public, anon, authenticated;
grant execute on function public.legal_summary_set(uuid, text, date, text, text) to service_role;

-- Checker: review only (no write).
create or replace function public.legal_summary_review(p_firm uuid)
 returns table(id uuid, title text, state text, summary text, summary_date date, summary_source_url text, summary_by text, history_n bigint)
 language sql
 stable
 security definer
 set search_path to 'public'
as $function$
  select i.id, i.title, i.state, i.summary, i.summary_date, i.summary_source_url, i.summary_by,
         (select count(*) from firm_legal_summary_history h where h.legal_item_id = i.id)
    from firm_legal_items i where i.firm_id = p_firm and i.grp in ('case', 'regulator') and not i.hidden
   order by i.summary is null, i.title
$function$;
revoke all on function public.legal_summary_review(uuid) from public, anon, authenticated;
grant execute on function public.legal_summary_review(uuid) to service_role;

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
        'summary', summary, 'summary_date', summary_date, 'summary_url', summary_source_url,
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
