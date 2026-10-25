-- Name-only (unconfirmed) sanctions hits: the check stays Clear, and the page shows which list
-- had the same name. Raw enrichment and submission payloads are not rewritten.
-- The Enricher records these as searches.result 'none' plus a note today; going forward a search
-- sets name_only=true, list, and check (see docs/ENRICHER.md). Derived rows only.

alter table public.firm_check_rows add column if not exists name_only text[];
alter table public.search_log add column if not exists name_only boolean not null default false;

-- search_log_current is select l.*, which is fixed at the view's creation. Replace it so the new column is visible.
create or replace view public.search_log_current with (security_invoker = true) as
  select l.*
  from search_log l
  where l.enrichment_id is null
     or l.enrichment_id = (select e2.id from research_enrichments e
                             join research_enrichments e2 on e2.valid and e2.bot_id = e.bot_id
                              and coalesce(e2.firm_id::text, e2.registry_id) = coalesce(e.firm_id::text, e.registry_id)
                            where e.id = l.enrichment_id
                            order by e2.received_at desc, e2.id desc limit 1);
revoke all on public.search_log_current from anon, authenticated, public;

-- Which of the 10 checks a list name belongs on. Anything else is sanctions (check 1).
create or replace function public._name_only_check(p_list text)
returns int
language sql
immutable
set search_path = public
as $$
  select case
    when coalesce(p_list, '') ~* 'itar|entity list|\mexport\M|debar|\mbis\M' then 3
    when coalesce(p_list, '') ~* 'terror' then 2
    when coalesce(p_list, '') ~* 'aml|fincen|money launder' then 5
    when coalesce(p_list, '') ~* '\mpep\M|politic' then 10
    else 1
  end
$$;

-- List name from one name-only sentence. The "across OFAC, UK and EU" trailer is the set of
-- lists that were screened, not lists the person appears on, so it is cut off. A surname-only
-- line is not this phrase. No recognized list means no note.
create or replace function public._name_only_list(p_win text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  w text := coalesce(p_win, '');
  rel int;
  pre text;
  post text;
  cut int;
  m text[];
begin
  if w = '' then return null; end if;
  rel := position('name-only match' in lower(w));
  if rel > 0 then
    -- "Screened against UK Sanctions List ... name-only match: EU consolidated list" names the
    -- source file first. The list the person appears on is the text after the phrase.
    -- ITAR is the exception: "Kan Chen ITAR name-only match" puts the list before the phrase.
    pre := substring(substring(w from 1 for rel - 1) from '[^\n]*$');
    post := substring(substring(w from rel + length('name-only match')) from '^[^\n]*');
  else
    pre := '';
    post := w;
  end if;
  cut := position(' across ' in lower(post));
  if cut > 0 then post := substring(post from 1 for cut - 1); end if;
  if position('://' in post) > 0 then
    post := regexp_replace(substring(post from 1 for position('://' in post) - 1), '[[:space:]—–-]+$', '');
  end if;
  m := regexp_match(post, 'ITAR Debarred \([A-Za-z0-9]+\)', 'i');
  if m is not null then return m[1]; end if;
  if post ~* '\mITAR\M' or pre ~* '\mITAR\M' then return 'ITAR Debarred'; end if;
  if post ~* 'UK Sanctions List' then return 'UK Sanctions List'; end if;
  if post ~* 'EU consolidated list' then return 'EU consolidated list'; end if;
  if post ~* 'Menu-Based Sanctions' then return 'Non-SDN Menu-Based Sanctions (NS-MBS)'; end if;
  if post ~* 'OFAC SDN' then return 'OFAC SDN'; end if;
  if post ~* 'Consolidated Screening List' then return 'Consolidated Screening List'; end if;
  return null;
end
$$;

-- Every "name-only match" in free text. A letter immediately before the phrase (surname-only match)
-- is not one. "name-only near match" is a different phrase and is ignored.
create or replace function public._name_only_from_text(p_text text)
returns table(n int, list_name text)
language plpgsql
immutable
set search_path = public
as $$
declare
  low text := lower(coalesce(p_text, ''));
  p int := 1;
  hit int;
  lst text;
  guard int := 0;
begin
  if low = '' then return; end if;
  loop
    guard := guard + 1;
    exit when guard > 30;
    hit := position('name-only match' in substring(low from p));
    exit when hit = 0;
    hit := p + hit - 1;
    if hit = 1 or substring(low from hit - 1 for 1) !~ '[a-z]' then
      lst := public._name_only_list(substring(p_text from greatest(hit - 80, 1) for 500));
      if lst is not null then
        n := public._name_only_check(lst);
        list_name := lst;
        return next;
      end if;
    end if;
    p := hit + 15;
  end loop;
end
$$;

-- Refresh firm_check_rows.name_only from the latest valid enrichment. Reads the payload; does not write it.
-- Does not change state or searched_at: firm_page shows Clear when the stored state is nc, clear, or nf.
create or replace function public._apply_name_only(p_firm uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare e public.research_enrichments;
begin
  update public.firm_check_rows set name_only = null where firm_id = p_firm and name_only is not null;
  select * into e from public.research_enrichments
   where firm_id = p_firm and valid
   order by received_at desc, id desc
   limit 1;
  if e.id is null then return; end if;
  with note_hits as (
    select n, list_name from public._name_only_from_text(e.payload->>'notes')
  ),
  search_hits as (
    select
      case
        when (s->>'check') ~ '^(10|[1-9])$' then (s->>'check')::int
        when h.n is not null and nullif(btrim(s->>'list'), '') is null then h.n
        else public._name_only_check(coalesce(nullif(left(btrim(s->>'list'), 200), ''), h.list_name))
      end as n,
      coalesce(nullif(left(btrim(s->>'list'), 200), ''), h.list_name) as list_name
    from jsonb_array_elements(case when jsonb_typeof(e.payload->'searches') = 'array' then e.payload->'searches' else '[]'::jsonb end) s
    left join lateral public._name_only_from_text(s->>'note') h on true
    where coalesce(s->>'name_only', '') in ('true', 't', '1')
       or lower(coalesce(s->>'note', '')) ~ '(^|[^a-z])name-only match'
  ),
  clean as (
    select n, list_name from note_hits
    union
    select n, list_name from search_hits
  ),
  pref as (
    select c.n, c.list_name
    from clean c
    where c.n between 1 and 10 and c.list_name is not null and btrim(c.list_name) <> ''
      and not exists (
        select 1 from clean o
        where o.n = c.n and o.list_name is not null
          and length(o.list_name) > length(c.list_name)
          and position(c.list_name in o.list_name) > 0
      )
  )
  update public.firm_check_rows r
     set name_only = s.lists
    from (
      select n, array_agg(distinct list_name order by list_name) as lists
      from pref
      group by n
    ) s
   where r.firm_id = p_firm and r.n = s.n;
end
$$;

revoke all on function public._name_only_check(text) from public, anon, authenticated;
revoke all on function public._name_only_list(text) from public, anon, authenticated;
revoke all on function public._name_only_from_text(text) from public, anon, authenticated;
revoke all on function public._apply_name_only(uuid) from public, anon, authenticated;
grant execute on function public._apply_name_only(uuid) to service_role;

-- Record the structured flag on the derived search log. The payload is still only read.
create or replace function public.search_log_from_enrichment(p_id bigint) returns int
language plpgsql security definer set search_path = public as $$
declare e research_enrichments; n int;
begin
  select * into e from research_enrichments where id = p_id;
  if e.id is null or not e.valid then return 0; end if;
  delete from search_log where enrichment_id = p_id;
  insert into search_log(firm_id, registry_id, bot_id, section, source_site, query, searched_at, result, item_count, enrichment_id, name_only)
  select e.firm_id, e.registry_id, e.bot_id, lower(s->>'section'),
    coalesce(nullif(lower(s->>'site'), ''), _dom(s->>'url'), _dom(s->>'query')), coalesce(s->>'query', s->>'url'),
    coalesce(case when s->>'searched_at' ~ '^\d{4}-\d{2}-\d{2}' then (s->>'searched_at')::timestamptz end, e.received_at),
    case when s->>'result' in ('found', 'none', 'blocked', 'error') then s->>'result' else 'error' end,
    coalesce(case when s->>'item_count' ~ '^\d+$' then (s->>'item_count')::int end, 0), e.id,
    coalesce(s->>'name_only', '') in ('true', 't', '1')
      or lower(coalesce(s->>'note', '')) ~ '(^|[^a-z])name-only match'
  from jsonb_array_elements(case when jsonb_typeof(e.payload->'searches') = 'array' then e.payload->'searches' else '[]' end) s
  where lower(s->>'section') in ('overview', 'checks', 'legal', 'people', 'board_seats', 'funds', 'timeline', 'press', 'founders', 'lps');
  insert into search_log(firm_id, registry_id, bot_id, section, source_site, query, searched_at, result, item_count, enrichment_id)
  select e.firm_id, e.registry_id, e.bot_id, sec, _dom(url), min(url), e.received_at, 'found', count(*), e.id
  from (select case when section = 'people' and txt ~* '\m(board|director)' then 'board_seats' else section end sec, url
        from enrichment_items(e.payload) where ok) x
  group by sec, _dom(url);
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.search_log_from_enrichment(bigint) from public, anon, authenticated;
CREATE OR REPLACE FUNCTION public.promote_enrichment(p_firm uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e research_enrichments; it record; rid uuid; n int := 0; i int := 0; f firms; dom text; handle text; t_t text; t_id uuid; t_c text;
  person text; chk text := to_char(now() at time zone 'America/Los_Angeles', 'Mon FMDD, YYYY'); cnt jsonb := '{}';
begin
  select * into f from firms where id = p_firm;
  if f.id is null then return '{}'; end if;
  select * into e from research_enrichments where firm_id = p_firm and valid order by received_at desc, id desc limit 1;
  -- remove only the rows a previous promotion created
  delete from fact_sources fs using enrichment_rows r where r.firm_id = p_firm and fs.fact_type = r.table_name and fs.fact_id = r.row_id;
  delete from firm_profile_facts x using enrichment_rows r where r.firm_id = p_firm and r.table_name = 'firm_profile_facts' and x.id = r.row_id;
  delete from firm_legal_items x using enrichment_rows r where r.firm_id = p_firm and r.table_name = 'firm_legal_items' and x.id = r.row_id;
  delete from firm_people_roles x using enrichment_rows r where r.firm_id = p_firm and r.table_name = 'firm_people_roles' and x.id = r.row_id;
  delete from timeline_events x using enrichment_rows r where r.firm_id = p_firm and r.table_name = 'timeline_events' and x.id = r.row_id;
  delete from founder_accounts x using enrichment_rows r where r.firm_id = p_firm and r.table_name = 'founder_accounts' and x.id = r.row_id;
  delete from press_item_firms x using enrichment_rows r where r.firm_id = p_firm and r.table_name = 'press_item_firms' and x.press_item_id = r.row_id and x.firm_id = p_firm;
  delete from enrichment_rows where firm_id = p_firm;
  update firm_corrections set active = false where firm_id = p_firm and active;
  delete from firm_owned_media where firm_id = p_firm and origin = 'enricher';
  if e.id is null then
    perform _apply_name_only(p_firm);
    return '{}';
  end if;
  -- owned media the enricher names (podcast, YouTube channel, newsletter, blog the firm runs): "owned_media": ["https://..."] or [{"url": "..."}]
  insert into firm_owned_media(firm_id, host, path, label, origin)
  select p_firm, _dom(u), coalesce(rtrim(substring(lower(u) from '://[^/]+(/[^?#]*)'), '/'), ''), nullif(o->>'label', ''), 'enricher'
    from jsonb_array_elements(case when jsonb_typeof(e.payload->'owned_media') = 'array' then e.payload->'owned_media' else '[]' end) o,
         lateral (select case jsonb_typeof(o) when 'string' then o #>> '{}' else coalesce(o->>'url', o->>'source') end u) z
   where _dom(u) is not null
  on conflict do nothing;
  dom := coalesce(nullif(f.primary_domain, ''), '~none~');
  handle := lower(regexp_replace(coalesce(nullif(f.short_name, ''), f.name), '[^A-Za-z0-9]', '', 'g'));
  for it in select * from enrichment_items(e.payload) where ok loop
    i := i + 1;
    rid := md5('enrich:' || p_firm || ':' || it.kind || ':' || it.section || ':' || coalesce(it.field, '') || ':' || it.txt || ':' || it.url)::uuid;
    -- fixes: override the matching displayed row when there is one (correction layer), else show as a correction item
    if it.kind = 'fix' then
      t_t := null; t_id := null; t_c := null; person := substring(it.field from '\[([^\]]+)\]');
      if it.section = 'people' and person is not null then
        select 'firm_people_roles' t, id, 'role' c into t_t, t_id, t_c from firm_people_roles
         where firm_id = p_firm and person_name ilike '%' || person || '%'
         order by person_name ilike person || '%' desc, id in (select row_id from enrichment_rows where firm_id = p_firm), sort_order limit 1;
      elsif lower(it.field) ~ '^(aum|facts\.aum)' then
        select 'firm_profile_facts' t, id, 'value' c into t_t, t_id, t_c from firm_profile_facts
         where firm_id = p_firm and hero_label in ('Assets', 'Regulatory AUM', 'AUM') order by origin nulls first limit 1;
      elsif lower(it.field) = 'hq' then
        select 'firm_profile_facts' t, id, 'value' c into t_t, t_id, t_c from firm_profile_facts
         where firm_id = p_firm and hero_label = 'HQ' order by origin nulls first limit 1;
      end if;
      insert into firm_corrections(id, firm_id, registry_id, enrichment_id, field, record_id, bot_value, correct_value, source_url, target_table, target_id, target_col)
      values (rid, p_firm, e.registry_id, e.id, it.field, it.record_id, it.bot_value, left(it.txt, 1000), it.url, t_t, t_id, t_c)
      on conflict (id) do update set active = true, enrichment_id = excluded.enrichment_id, target_table = excluded.target_table,
        target_id = excluded.target_id, target_col = excluded.target_col;
      perform _enrich_cite(p_firm, 'firm_corrections', rid, it.url, chk);
      insert into enrichment_rows values (p_firm, 'firm_corrections', rid, e.id) on conflict do nothing;
      if t_id is not null then n := n + 1; continue; end if;
    end if;
    if it.section in ('overview', 'funds', 'lps') then
      insert into firm_profile_facts(id, firm_id, section, label, value, sort_order, origin)
      values (rid, p_firm, it.section,
        case it.kind when 'fix' then 'Correction' when 'lead' then 'Lead (unverified)'
          else case it.section when 'overview' then 'Overview' when 'funds' then 'Funds' else 'Limited partners' end end,
        left(it.txt, 600), 500 + i, 'enricher submission ' || e.id) on conflict (id) do nothing;
      perform _enrich_cite(p_firm, 'firm_profile_facts', rid, it.url, chk);
      insert into enrichment_rows values (p_firm, 'firm_profile_facts', rid, e.id) on conflict do nothing;
    elsif it.section = 'legal' then
      insert into firm_legal_items(id, firm_id, grp, title, year_label, state, status_label, tone, note, sort_order)
      values (rid, p_firm,
        case when _dom(it.url) ~ '(courtlistener\.com|uscourts\.gov|pacer\.gov|justia\.com|law360\.com|casetext\.com)$' then 'case'
             when _dom(it.url) ~ '(sec\.gov|finra\.org|fca\.org\.uk)$' then 'regulator' else 'context' end,
        left(case when it.kind = 'lead' or it.txt ~* '^\s*lead\b' or it.txt ~* '\m(alleg|claim(s|ed)? that)' then
               case when it.txt ~* '^\s*lead\b' then it.txt else 'Lead (allegation, not verified): ' || it.txt end
             when it.kind = 'fix' then 'Correction: ' || it.txt else it.txt end, 600),
        substring(coalesce(it.date_label, it.txt) from '((19|20)\d{2})'),
        case when it.kind = 'lead' or it.txt ~* '^\s*lead\b' or it.txt ~* '\malleg' then 'Unverified'
             when it.txt ~* '(dismissed|terminated|settled|closed|judgment|vacated)' then 'Closed' end,
        case when it.kind = 'lead' or it.txt ~* '^\s*lead\b' or it.txt ~* '\malleg' then 'Lead · allegation' end,
        null, null, 500 + i) on conflict (id) do nothing;
      perform _enrich_cite(p_firm, 'firm_legal_items', rid, it.url, chk);
      insert into enrichment_rows values (p_firm, 'firm_legal_items', rid, e.id) on conflict do nothing;
    elsif it.section = 'people' then
      insert into firm_people_roles(id, firm_id, kind, person_name, role, badge, sort_order)
      values (rid, p_firm,
        case when it.txt ~* '\m(board|director)' then 'board' when it.txt ~* '\m(left|joined|former|depart|hired|promoted)' then 'move' else 'officer' end,
        left(it.txt, 600), '', case it.kind when 'fix' then 'Correction' when 'lead' then 'Lead (unverified)' end, 500 + i) on conflict (id) do nothing;
      perform _enrich_cite(p_firm, 'firm_people_roles', rid, it.url, chk);
      insert into enrichment_rows values (p_firm, 'firm_people_roles', rid, e.id) on conflict do nothing;
    elsif it.section = 'timeline' then
      insert into timeline_events(id, firm_id, date_label, kind, body, sort_order)
      values (rid, p_firm, coalesce(nullif(it.date_label, ''), 'Undated'), 'Reported', left(it.txt, 600),
        500 - coalesce(substring(it.date_label from '^(\d{4})')::int - 1900, 0)) on conflict (id) do nothing;
      perform _enrich_cite(p_firm, 'timeline_events', rid, it.url, chk);
      insert into enrichment_rows values (p_firm, 'timeline_events', rid, e.id) on conflict do nothing;
    elsif it.section = 'founders' then
      insert into founder_accounts(id, firm_id, outlet, date_label, headline, url, snippet, sort_order, independent)
      values (rid, p_firm, coalesce(nullif(it.outlet, ''), source_label(_dom(it.url), it.url)),
        coalesce(substring(it.who from '(\d{4}-\d{2}-\d{2})'), it.date_label),
        left(coalesce(it.who, it.txt), 300), it.url, left(it.txt, 600), 500 + i, not _own_media(p_firm, it.url))
      on conflict (id) do nothing;
      perform _enrich_cite(p_firm, 'founder_accounts', rid, it.url, chk);
      insert into enrichment_rows values (p_firm, 'founder_accounts', rid, e.id) on conflict do nothing;
    elsif it.section = 'press' then
      select id into rid from press_items where url = it.url order by created_at limit 1;
      if rid is null then
        rid := md5('enrich-press:' || it.url)::uuid;
        insert into press_items(id, publisher, domain, url, published_on, published_label, headline, snippet, data_status, retrieved_at, source_system)
        values (rid, coalesce(nullif(it.outlet, ''), source_label(_dom(it.url), it.url)), _dom(it.url), it.url,
          case when it.date_label ~ '^\d{4}-\d{2}-\d{2}$' then it.date_label::date end, it.date_label,
          left(it.txt, 400), left(it.who, 600), 'real', now(), 'enricher') on conflict (id) do nothing;
      end if;
      if not exists (select 1 from press_item_firms where press_item_id = rid and firm_id = p_firm) then
        insert into press_item_firms(press_item_id, firm_id, sort_order) values (rid, p_firm, 500 + i);
        insert into enrichment_rows values (p_firm, 'press_item_firms', rid, e.id) on conflict do nothing;
      end if;
    else
      continue;  -- checks: stored raw (firm_check_rows are managed by the check pipeline)
    end if;
    n := n + 1;
  end loop;
  select coalesce(jsonb_object_agg(table_name, c), '{}') into cnt from (select table_name, count(*) c from enrichment_rows where firm_id = p_firm group by 1) x;
  perform _apply_name_only(p_firm);
  return cnt || jsonb_build_object('promoted', n, 'enrichment_id', e.id);
end $function$;

create or replace function public.firm_page(p_slug text, p_anon uuid, p_spend boolean default false, p_email text default null)
returns json language plpgsql security definer set search_path = public as $$
declare f firms; u json; open boolean; secs jsonb := '[]'; s page_sections; it jsonb; hero jsonb; q research_queue; qid text;
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
    if not f.indexable and jsonb_array_length(hero) = 0 then
      select coalesce(jsonb_agg(jsonb_build_object('label', l, 'value', v, 'anchor', 'overview', 'src', '[]'::jsonb) order by o), '[]') into hero
        from (values (1, 'HQ', f.hq), (2, 'SEC CRD', nullif(q.sec_crd, '')), (3, 'LEI', nullif(q.lei, ''))) x(o, l, v) where v is not null;
    end if;
    return json_build_object('status', 'ok', 'open', false, 'locked', u->>'status', 'unchecked', not f.indexable,
      'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', f.hq),
      'hero', hero, 'sections', '[]'::json, 'done', _firm_checks_done(f.id),
      'checks', (select json_agg(json_build_object('n', n, 'title', title, 'descr', descr, 'state', null, 'count', null, 'searched_at', null,
          'items', null, 'itemized', null, 'name_only', null) order by n) from firm_check_rows where firm_id = f.id),
      'queue', q.status, 'started_at', case when q.status = 'claimed' then q.claimed_at end, 'details', null, 'outline', null,
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
    'queue', q.status, 'started_at', case when q.status = 'claimed' then q.claimed_at end,
    'details', u->'details', 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon));
end $$;
revoke all on function public.firm_page(text, uuid, boolean, text) from public;
grant execute on function public.firm_page(text, uuid, boolean, text) to anon, authenticated, service_role;
-- Derived rows only. Payloads stay as stored.
select public._apply_name_only(f.id)
from public.firms f
where exists (
  select 1 from public.research_enrichments e
  where e.firm_id = f.id and e.valid
);
