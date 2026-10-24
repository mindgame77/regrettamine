-- Enricher ingest (toxy-enricher): raw enrichment submissions, promotion onto the page tables ON TOP of the friend's data,
-- a correction/override layer for fixes, a per-site search log, per-firm section status, and a feedback loop for
-- repeated portal-night-bot mistakes. Raw data (research_submissions, research_enrichments) is never modified by promotion.
-- No design change: rows land in the existing sections that firm_page() already renders.

-- 1. raw enrichment submissions (append-only; kept for audit even when invalid)
create table if not exists public.research_enrichments (
  id bigint generated always as identity primary key,
  bot_id text not null,
  registry_id text,
  slug text,
  firm_id uuid references public.firms(id) on delete set null,
  payload jsonb not null,
  valid boolean not null default true,
  errors jsonb,
  accepted int not null default 0,
  rejected int not null default 0,
  received_at timestamptz not null default now()
);
create index if not exists research_enrichments_firm_idx on public.research_enrichments (firm_id, received_at desc);
create index if not exists research_enrichments_reg_idx on public.research_enrichments (registry_id, received_at desc);
alter table public.research_enrichments enable row level security;
revoke all on public.research_enrichments from anon, authenticated, public;

-- 2. rows the promotion created (so a re-promotion replaces only its own rows; never the friend's)
create table if not exists public.enrichment_rows (
  firm_id uuid not null references public.firms(id) on delete cascade,
  table_name text not null,
  row_id uuid not null,
  enrichment_id bigint not null,
  primary key (table_name, row_id, firm_id)
);
alter table public.enrichment_rows enable row level security;
revoke all on public.enrichment_rows from anon, authenticated, public;

-- 3. correction / override layer: a fix overrides one displayed column of one row; the row itself is never edited
create table if not exists public.firm_corrections (
  id uuid primary key,
  firm_id uuid references public.firms(id) on delete cascade,
  registry_id text,
  enrichment_id bigint not null,
  field text,
  record_id text,
  bot_value text,
  correct_value text not null,
  source_url text,
  target_table text,
  target_id uuid,
  target_col text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists firm_corrections_target_idx on public.firm_corrections (target_table, target_id) where active;
alter table public.firm_corrections enable row level security;
revoke all on public.firm_corrections from anon, authenticated, public;

-- founder accounts from a firm-owned source are not independent
alter table public.founder_accounts add column if not exists independent boolean not null default true;

-- 4. per-site search log
create table if not exists public.search_log (
  id bigint generated always as identity primary key,
  firm_id uuid references public.firms(id) on delete set null,
  registry_id text,
  bot_id text not null,
  section text not null,
  source_site text,
  query text,
  searched_at timestamptz,
  result text not null check (result in ('found', 'none', 'blocked', 'error')),
  item_count int not null default 0,
  enrichment_id bigint,
  submission_id bigint,
  created_at timestamptz not null default now()
);
create index if not exists search_log_firm_idx on public.search_log (firm_id, section);
create index if not exists search_log_reg_idx on public.search_log (registry_id, section);
create unique index if not exists search_log_sub_uq on public.search_log (submission_id, section, coalesce(source_site, ''), coalesce(query, '')) where submission_id is not null;
alter table public.search_log enable row level security;
revoke all on public.search_log from anon, authenticated, public;

-- 5. source rules: a source is required; .gov/.mil/embassy blocked except SEC; courts allowed (CourtListener, uscourts, PACER)
create or replace function public._enrich_src_ok(u text) returns boolean language sql immutable set search_path = public as $$
  select coalesce(u, '') ~* '^https?://[^\s/]+\.[^\s]+$'
     and coalesce(u, '') !~* '(google\.[a-z.]+/search|bing\.com/search|duckduckgo\.com/\?|grok\.com|x\.com/i/grok|chatgpt\.com|perplexity\.ai/search)'
     and (public._promo_src_ok(u)
          or coalesce(substring(lower(u) from '://(?:www\.)?([^/:]+)'), '') ~ '(^|\.)(courtlistener\.com|uscourts\.gov|pacer\.gov)$') $$;
create or replace function public._dom(u text) returns text language sql immutable as $$
  select substring(lower(coalesce(u, '')) from '://(?:www\.)?([^/:?#]+)') $$;

-- section of a confirm/fix/add/lead field name
create or replace function public._enrich_section(fld text) returns text language sql immutable as $$
  select case
    when f ~ '^(hq|founded|legal_entities|history|predecessor|structure|ownership|related_adviser|website|entities|non_us)' then 'overview'
    when f ~ '^(aum|facts\.aum|funds|latestraise|fundraise|terms)' then 'funds'
    when f ~ '^(limitedpartners|limited_partners|lps)' then 'lps'
    when f ~ '^board' then 'people'
    when f ~ '^(people|pep)' then 'people'
    when f ~ '^(lawsuits|litigation|legal|regulatory|controversies|lead|sanctions|politicalcontext)' then 'legal'
    when f ~ '^(press|posts)' then 'press'
    when f ~ '^founder' then 'founders'
  end from (select lower(coalesce(fld, '')) f) x $$;

-- 6. every promotable item of one enrichment payload, with its verdict (accepted or rejected + reason)
create or replace function public.enrichment_items(p jsonb)
returns table(kind text, section text, field text, txt text, url text, date_label text, outlet text, who text, record_id text,
              bot_value text, ok boolean, reason text)
language sql immutable set search_path = public as $$
  with raw as (
    select 'section' kind,
      case s.key when 'Overview' then 'overview' when 'The 10 checks' then 'checks' when 'Legal & regulatory' then 'legal'
        when 'People & board seats' then 'people' when 'Funds' then 'funds' when 'Timeline' then 'timeline'
        when 'Press coverage' then 'press' when 'What founders say' then 'founders' else lower(s.key) end section,
      null::text field, coalesce(i->>'item', i->>'headline', i->>'quote') txt, coalesce(i->>'source', i->>'url') url,
      i->>'date' date_label, i->>'outlet' outlet, coalesce(i->>'who', i->>'snippet') who, null::text record_id, null::text bot_value
    from jsonb_each(case when jsonb_typeof(p->'sections') = 'object' then p->'sections' else '{}' end) s,
         jsonb_array_elements(case when jsonb_typeof(s.value) = 'array' then s.value else '[]' end) i
    union all
    select g.k, _enrich_section(i->>'field'), i->>'field',
      coalesce(i->>'correct_value', i->>'value'), coalesce(i->>'source_url', i->>'source', i->>'url'), i->>'date', null, null,
      i->>'record_id', i->>'bot_value'
    from (values ('add'), ('fix'), ('lead')) g(k),
         jsonb_array_elements(case when jsonb_typeof(p->(case g.k when 'lead' then 'leads' else g.k end)) = 'array' then p->(case g.k when 'lead' then 'leads' else g.k end) else '[]' end) i
  )
  select kind, section, field, txt, url, date_label, outlet, who, record_id, bot_value,
    reason is null, reason
  from (select r.*, case
      when nullif(trim(coalesce(txt, '')), '') is null then 'empty item'
      when nullif(trim(coalesce(url, '')), '') is null then 'no source URL'
      when url !~* '^https?://[^\s/]+\.[^\s]+$' then 'source is not a URL'
      when not _enrich_src_ok(url) then 'source not allowed (.gov/.mil other than SEC and courts, or a search/chat page)'
      when section is null then 'field has no page section (kept raw only)'
      when lower(coalesce(field, '')) ~ '^(aum|facts\.aum)' and kind <> 'lead' and txt !~ '\d' then 'AUM needs a numeric figure'
      when section = 'press' and kind = 'section' and coalesce(outlet, '') = '' then 'press item needs outlet + headline + url'
    end reason from raw r) x $$;

-- 7. promote the latest valid enrichment of one firm onto the page tables (idempotent; replaces only its own rows)
create or replace function public._enrich_cite(p_firm uuid, p_type text, p_id uuid, p_url text, p_date text) returns void
language plpgsql security definer set search_path = public as $$
declare sid uuid;
begin
  insert into sources(url, domain, publisher, retrieved_at, data_status, source_system)
  values (p_url, _dom(p_url), _dom(p_url), now(), 'real', 'enricher') on conflict (url) do nothing;
  select id into sid from sources where url = p_url;
  insert into fact_sources(id, source_id, firm_id, fact_type, fact_id, label, date_label, sort_order, data_status)
  values (md5(p_id || ':' || p_url)::uuid, sid, p_firm, p_type, p_id, _dom(p_url), p_date, 0, 'real') on conflict (id) do nothing;
end $$;

create or replace function public.promote_enrichment(p_firm uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e research_enrichments; it record; rid uuid; n int := 0; i int := 0; f firms; dom text; handle text; tgt record;
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
  if e.id is null then return '{}'; end if;
  dom := coalesce(nullif(f.primary_domain, ''), '~none~');
  handle := lower(regexp_replace(coalesce(nullif(f.short_name, ''), f.name), '[^A-Za-z0-9]', '', 'g'));
  for it in select * from enrichment_items(e.payload) where ok loop
    i := i + 1;
    rid := md5('enrich:' || p_firm || ':' || it.kind || ':' || it.section || ':' || coalesce(it.field, '') || ':' || it.txt || ':' || it.url)::uuid;
    -- fixes: override the matching displayed row when there is one (correction layer), else show as a correction item
    if it.kind = 'fix' then
      tgt := null; person := substring(it.field from '\[([^\]]+)\]');
      if it.section = 'people' and person is not null then
        select 'firm_people_roles' t, id, 'role' c into tgt from firm_people_roles
         where firm_id = p_firm and person_name ilike '%' || person || '%'
           and id not in (select row_id from enrichment_rows where firm_id = p_firm) order by sort_order limit 1;
      elsif lower(it.field) ~ '^(aum|facts\.aum)' then
        select 'firm_profile_facts' t, id, 'value' c into tgt from firm_profile_facts
         where firm_id = p_firm and hero_label in ('Assets', 'Regulatory AUM', 'AUM') order by origin nulls first limit 1;
      elsif lower(it.field) = 'hq' then
        select 'firm_profile_facts' t, id, 'value' c into tgt from firm_profile_facts
         where firm_id = p_firm and hero_label = 'HQ' order by origin nulls first limit 1;
      end if;
      insert into firm_corrections(id, firm_id, registry_id, enrichment_id, field, record_id, bot_value, correct_value, source_url, target_table, target_id, target_col)
      values (rid, p_firm, e.registry_id, e.id, it.field, it.record_id, it.bot_value, left(it.txt, 1000), it.url, tgt.t, tgt.id, tgt.c)
      on conflict (id) do update set active = true, enrichment_id = excluded.enrichment_id, target_table = excluded.target_table,
        target_id = excluded.target_id, target_col = excluded.target_col;
      perform _enrich_cite(p_firm, 'firm_corrections', rid, it.url, chk);
      insert into enrichment_rows values (p_firm, 'firm_corrections', rid, e.id) on conflict do nothing;
      if tgt.id is not null then n := n + 1; continue; end if;
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
      select rid, p_firm,
        coalesce(nullif(it.outlet, ''), source_label(_dom(it.url), it.url)) || case when fo then ' · firm-owned, not independent' else '' end,
        coalesce(substring(it.who from '(\d{4}-\d{2}-\d{2})'), it.date_label),
        left(coalesce(it.who, it.txt), 300), it.url, left(it.txt, 600), 500 + i, not fo
      from (select (_dom(it.url) = dom or _dom(it.url) like '%.' || dom
                    or (_dom(it.url) in ('x.com', 'twitter.com', 'linkedin.com', 'medium.com', 'youtube.com')
                        and lower(it.url) ~ ('^https?://(www\.)?[^/]+/(company/)?@?' || handle || '[^a-z0-9]'))) fo) z
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
  return cnt || jsonb_build_object('promoted', n, 'enrichment_id', e.id);
end $$;
revoke all on function public.promote_enrichment(uuid) from public, anon, authenticated;
grant execute on function public.promote_enrichment(uuid) to service_role;

-- override lookups used by _sec_items
create or replace function public._ovr(p_table text, p_id uuid, p_col text) returns text language sql stable set search_path = public as $$
  select correct_value from firm_corrections where active and target_table = p_table and target_id = p_id and target_col = p_col
  order by created_at desc limit 1 $$;
create or replace function public._ovr_src(p_table text, p_id uuid) returns jsonb language sql stable set search_path = public as $$
  select coalesce((select _src('firm_corrections', c.id) from firm_corrections c
    where c.active and c.target_table = p_table and c.target_id = p_id order by c.created_at desc limit 1), '[]'::jsonb) $$;

-- same output as before; corrected rows show the corrected value plus the correction's source
CREATE OR REPLACE FUNCTION public._sec_items(p_key text, p_firm uuid)
 RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(it order by o), '[]') from (
    select jsonb_build_object('head', label || ': ' || v, 'label', label, 'value', v, 'src', _src('firm_profile_facts', id) || _ovr_src('firm_profile_facts', id)) it, sort_order o
      from (select *, coalesce(_ovr('firm_profile_facts', id, 'value'), value) v from firm_profile_facts where firm_id = p_firm and section = p_key and p_key in ('overview', 'funds', 'lps')) ff
    union all
    select jsonb_build_object('head', 'Check ' || n || ': ' || title, 'n', n, 'title', title, 'descr', descr, 'state', state, 'count', count_label, 'src', '[]'::jsonb), n
      from firm_check_rows where firm_id = p_firm and p_key = 'checks'
    union all
    select jsonb_build_object('head', title, 'grp', grp, 'year', year_label, 'role', role, 'state', state, 'status', status_label, 'tone', tone, 'note', coalesce(_ovr('firm_legal_items', id, 'note'), note),
        'src', _src('firm_legal_items', id) || _ovr_src('firm_legal_items', id)), case grp when 'case' then 0 when 'regulator' then 1000 else 2000 end + sort_order
      from firm_legal_items where firm_id = p_firm and p_key = 'legal'
    union all
    select jsonb_build_object('head', p.headline, 'outlet', source_label(p.publisher, p.url), 'date', p.published_label, 'url', p.url, 'snippet', p.snippet, 'logo', p.logo_path, 'group', p.group_label,
        'src', jsonb_build_array(jsonb_build_object('label', source_label(p.publisher, p.url), 'date', p.published_label, 'url', p.url))), pf.sort_order
      from press_items p join press_item_firms pf on pf.press_item_id = p.id
      where pf.firm_id = p_firm and p_key = 'press' and p.data_status = 'real' and p.url <> ''
    union all
    select jsonb_build_object('head', headline, 'outlet', outlet, 'date', date_label, 'url', url, 'snippet', snippet, 'src', _src('founder_accounts', id)), sort_order
      from founder_accounts where firm_id = p_firm and p_key = 'founders'
    union all
    select jsonb_build_object('head', person_name, 'kind', kind, 'role', coalesce(_ovr('firm_people_roles', id, 'role'), role),
        'badge', case when _ovr('firm_people_roles', id, 'role') is not null then 'Corrected' else badge end,
        'src', _src('firm_people_roles', id) || _ovr_src('firm_people_roles', id)),
        case kind when 'board' then 0 when 'move' then 1000 else 2000 end + sort_order
      from firm_people_roles where firm_id = p_firm and p_key = 'people'
    union all
    select jsonb_build_object('head', date_label || ' · ' || body, 'date', date_label, 'kind', kind, 'body', body, 'src', _src('timeline_events', id)), sort_order
      from timeline_events where firm_id = p_firm and p_key = 'timeline'
  ) x where p_key in ('checks', 'press') or jsonb_array_length(it->'src') > 0
$function$;

-- 8. search log fill
create or replace function public._section_of_checklist(ci text) returns text language sql immutable as $$
  select case
    when c ~ '(board_seat|^b3)' then 'board_seats'
    when c ~ '^(people|b4|people_screen)' then 'people'
    when c ~ '^(identity|a1|a5|a6|registration|identifiers|legal_entities|ownership)' then 'overview'
    when c ~ '^(fund|funds|limitedpartners|a7|adv_counts|c3|portfolio)' then 'funds'
    when c ~ '^(f4|media_reach|posts|social)' then 'press'
    when c ~ '^(f3|experience\.founder|gov\.founder_sentiment|reviews)' then 'founders'
    when c ~ '^(legal|reg\.|fraud|courts|sanctions|conduct|gov\.|g legal|workplace|security|lobbying|controversies|distress|government|crypto|company)' then 'legal'
  end from (select lower(coalesce(ci, '')) c) x $$;

create or replace function public.search_log_from_enrichment(p_id bigint) returns int
language plpgsql security definer set search_path = public as $$
declare e research_enrichments; n int;
begin
  select * into e from research_enrichments where id = p_id;
  if e.id is null or not e.valid then return 0; end if;
  delete from search_log where enrichment_id = p_id;
  -- explicit searches the bot logged
  insert into search_log(firm_id, registry_id, bot_id, section, source_site, query, searched_at, result, item_count, enrichment_id)
  select e.firm_id, e.registry_id, e.bot_id, lower(s->>'section'),
    coalesce(nullif(lower(s->>'site'), ''), _dom(s->>'url'), _dom(s->>'query')), coalesce(s->>'query', s->>'url'),
    coalesce(case when s->>'searched_at' ~ '^\d{4}-\d{2}-\d{2}' then (s->>'searched_at')::timestamptz end, e.received_at),
    case when s->>'result' in ('found', 'none', 'blocked', 'error') then s->>'result' else 'error' end,
    coalesce(case when s->>'item_count' ~ '^\d+$' then (s->>'item_count')::int end, 0), e.id
  from jsonb_array_elements(case when jsonb_typeof(e.payload->'searches') = 'array' then e.payload->'searches' else '[]' end) s
  where lower(s->>'section') in ('overview', 'checks', 'legal', 'people', 'board_seats', 'funds', 'timeline', 'press', 'founders', 'lps');
  -- every accepted sourced item implies a successful visit to its site
  insert into search_log(firm_id, registry_id, bot_id, section, source_site, query, searched_at, result, item_count, enrichment_id)
  select e.firm_id, e.registry_id, e.bot_id, sec, _dom(url), min(url), e.received_at, 'found', count(*), e.id
  from (select case when section = 'people' and txt ~* '\m(board|director)' then 'board_seats' else section end sec, url
        from enrichment_items(e.payload) where ok) x
  group by sec, _dom(url);
  get diagnostics n = row_count;
  return n;
end $$;

-- existing friend submissions: search_log entries + coverage statuses (blocked / none_found), read-only on the raw rows
create or replace function public.search_log_from_submission(p_id bigint) returns int
language plpgsql security definer set search_path = public as $$
declare s research_submissions; n int;
begin
  select * into s from research_submissions where id = p_id;
  if s.id is null or not s.valid then return 0; end if;
  insert into search_log(firm_id, registry_id, bot_id, section, source_site, query, searched_at, result, item_count, submission_id)
  select null, s.registry_id, coalesce(s.bot_id, 'unknown'), sec, site, left(q->>'query', 500),
    coalesce(case when q->>'executed_at' ~ '^\d{4}-\d{2}-\d{2}' then (q->>'executed_at')::timestamptz end, s.received_at),
    case when cst = 'blocked' then 'blocked' when cst = 'records' then 'found' when cst = 'none_found' then 'none'
         when coalesce(case when q->>'results_count' ~ '^\d+$' then (q->>'results_count')::int end, 0) > 0
           or jsonb_array_length(coalesce(q->'kept_urls', '[]')) > 0 then 'found' else 'none' end,
    greatest(jsonb_array_length(coalesce(q->'kept_urls', '[]')), 0), s.id
  from (select q, coalesce(_section_of_checklist(q->>'checklist_item'), (select _section_of_checklist(c->>'checklist_item')
          from jsonb_array_elements(case when jsonb_typeof(s.payload->'coverage') = 'array' then s.payload->'coverage' else '[]' end) c
          where jsonb_typeof(c->'query_ids') = 'array' and c->'query_ids' ? (q->>'query_id') limit 1)) sec,
          coalesce(_dom(q->'kept_urls'->>0), nullif(lower(q->>'tool'), ''), 'web') site,
          (select c->>'status' from jsonb_array_elements(case when jsonb_typeof(s.payload->'coverage') = 'array' then s.payload->'coverage' else '[]' end) c
            where (jsonb_typeof(c->'query_ids') = 'array' and c->'query_ids' ? (q->>'query_id')) or c->>'checklist_item' = q->>'checklist_item'
            order by (jsonb_typeof(c->'query_ids') = 'array' and c->'query_ids' ? (q->>'query_id')) desc limit 1) cst
        from jsonb_array_elements(case when jsonb_typeof(s.payload->'search_log') = 'array' then s.payload->'search_log' else '[]' end) q) x
  where sec is not null
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

-- 9. per-site views
create or replace view public.firm_site_coverage as
  select coalesce(f.slug, l.registry_id) firm, l.firm_id, l.registry_id, l.section, l.source_site,
    count(*) searches, count(*) filter (where result = 'found') found, count(*) filter (where result = 'none') none,
    count(*) filter (where result = 'blocked') blocked, count(*) filter (where result = 'error') error,
    sum(item_count) items, max(searched_at) last_searched
  from search_log l left join firms f on f.id = l.firm_id
  group by 1, 2, 3, 4, 5;
create or replace view public.site_search_stats as
  select source_site, count(*) searches, count(distinct coalesce(firm_id::text, registry_id)) firms,
    round(avg((result = 'found')::int), 3) found_rate, round(avg((result = 'none')::int), 3) none_rate,
    round(avg((result = 'blocked')::int), 3) blocked_rate, round(avg((result = 'error')::int), 3) error_rate
  from search_log group by 1;
revoke all on public.firm_site_coverage, public.site_search_stats from anon, authenticated, public;

-- 10. firm_section_status (data only) + next_firms_to_enrich
create or replace view public.firm_section_status as
with fq as (
  select f.id firm_id, f.slug, f.name, f.published, _firm_queue_id(f.id) registry_id from firms f
   where f.deleted_at is null and not coalesce(f.is_test, false) and (f.published or f.launch_page)

  -- queued = firms on the publish queue (launch_page). The 7k-row research registry is not a page queue and is left out.
), base as (
  select fq.*, s.sec,
    case when fq.firm_id is null then false
         when s.sec = 'checks' then exists (select 1 from firm_check_rows c where c.firm_id = fq.firm_id and c.source_submission is not null)
         when s.sec = 'board_seats' then exists (select 1 from firm_people_roles p where p.firm_id = fq.firm_id and p.kind = 'board'
                                                  and exists (select 1 from fact_sources x where x.fact_type = 'firm_people_roles' and x.fact_id = p.id))
         else jsonb_array_length(_sec_items(s.sec, fq.firm_id)) > 0 end filled
  from fq cross join (values ('overview'), ('checks'), ('legal'), ('people'), ('board_seats'), ('funds'), ('timeline'), ('press'), ('founders')) s(sec)
), sec as (
  select b.firm_id, b.slug, b.name, b.published, b.registry_id, b.sec item,
    case when b.filled then 'filled'
         when exists (select 1 from search_log l where l.section = b.sec and l.result = 'none' and l.searched_at is not null
                        and (l.firm_id = b.firm_id or l.registry_id = b.registry_id)) then 'searched_none'
         else 'missing' end status,
    (select max(searched_at) from search_log l where l.section = b.sec and (l.firm_id = b.firm_id or l.registry_id = b.registry_id)) last_searched
  from base b
), chk as (
  select distinct fq.firm_id, fq.slug, fq.name, fq.published, fq.registry_id, 'checklist:' || (c->>'checklist_item') item,
    case when c->>'status' = 'blocked' then 'blocked' else 'not_searched' end status, null::timestamptz last_searched
  from fq join lateral (select payload from research_submissions s where s.registry_id = fq.registry_id and s.valid order by received_at desc, id desc limit 1) ls on true,
       jsonb_array_elements(coalesce(ls.payload->'coverage', '[]')) c
  where c->>'status' in ('blocked', 'not_searched')
), allx as (select * from sec union all select * from chk)
select a.*, count(*) filter (where status in ('filled', 'searched_none')) over w done,
  count(*) over w total,
  round(count(*) filter (where status in ('filled', 'searched_none')) over w::numeric / count(*) over w, 3) score
from allx a window w as (partition by coalesce(a.firm_id::text, a.registry_id));
revoke all on public.firm_section_status from anon, authenticated, public;

create or replace function public.next_firms_to_enrich(p_limit int default 20)
returns table(slug text, registry_id text, name text, published boolean, score numeric, done bigint, total bigint, missing text[])
language sql stable security definer set search_path = public as $$
  select slug, registry_id, name, published, score, done, total,
    array_agg(item order by item) filter (where status not in ('filled', 'searched_none'))
  from firm_section_status group by 1, 2, 3, 4, 5, 6, 7
  order by published desc, score asc, name limit greatest(1, least(coalesce(p_limit, 20), 500)) $$;
revoke all on function public.next_firms_to_enrich(int) from public, anon, authenticated;
grant execute on function public.next_firms_to_enrich(int) to service_role;

-- 11. feedback loop for repeated portal-night-bot mistakes (>= threshold distinct firms per pattern)
create table if not exists public.feedback_patterns (
  key text primary key,
  bot_prefix text not null default 'portal-night-bot',
  regex text not null,
  field_regex text,
  rule text not null,
  threshold int not null default 3,
  feedback_id bigint,
  activated_at timestamptz,
  baseline_firms int,
  baseline_reviewed int,
  last_firms int,
  last_reviewed int,
  examples jsonb,
  updated_at timestamptz not null default now()
);
alter table public.feedback_patterns enable row level security;
revoke all on public.feedback_patterns from anon, authenticated, public;
insert into public.feedback_patterns(key, regex, field_regex, rule) values
 ('fec_false_match', '\mfec\M.*(not the same|different|false|name[- ]only|no evidence|unrelated|homonym|common name|not .*match)|(not the same|different|false).*\mfec\M', null,
  'FEC donations: only record a contribution when the donor''s employer/occupation or city ties it to this person at this firm. A same-name FEC hit is not a match; leave it out.'),
 ('schedule_d_as_aum', '(gross assets?|schedule d).*(aum|regulatory assets|assets under management)|(aum|regulatory assets).*(gross assets?|schedule d)', null,
  'AUM: report regulatory AUM only from Form ADV Item 5F (raum_usd). Schedule D fund gross assets are not regulatory AUM; label them "fund gross assets (Schedule D)".'),
 ('exited_as_current', '(acquired|exited|ipo|merged|shut ?down|defunct|went public|sold to).*(not current|no longer|historical|exited|current)|current_status', '^portfolio',
  'Portfolio: check whether a company was acquired, went public or shut down. Mark exited companies as exited with the date; do not show them as current.'),
 ('formd_portfolio_people', 'form d.*(portfolio|company|issuer)|(portfolio|issuer).*form d', '^people',
  'People: names on a portfolio company''s Form D are that company''s officers/directors, not the firm''s people. Only list them as the firm''s partner when the firm''s own ADV or site confirms it.'),
 ('wrong_role', '(role|title|former|not a (partner|member)|left the firm|departed|no longer)', '^people',
  'People roles: take the role and dates from ADV Schedule A or the firm''s own team page, and mark people who left as former with the end date.')
on conflict (key) do nothing;

create or replace function public.refresh_feedback_patterns() returns jsonb
language plpgsql security definer set search_path = public as $$
declare p feedback_patterns; nf int; nr int; ex jsonb; msg text; fid bigint; out jsonb := '[]';
begin
  for p in select * from feedback_patterns loop
    -- latest enrichment per firm whose reviewed submission came from this bot
    with rev as (
      select distinct on (coalesce(e.firm_id::text, e.registry_id)) e.*, s.received_at sub_at
      from research_enrichments e join research_submissions s on s.id = case when e.payload->>'submission_id' ~ '^\d+$' then (e.payload->>'submission_id')::bigint end
      where e.valid and s.bot_id like p.bot_prefix || '%'
      order by coalesce(e.firm_id::text, e.registry_id), e.received_at desc, e.id desc
    ), hit as (
      select r.id, r.registry_id, coalesce(r.slug, r.registry_id) firm, x.t
      from rev r, lateral (
        select i::text t from jsonb_array_elements(case when jsonb_typeof(r.payload->'fix') = 'array' then r.payload->'fix' else '[]' end) i
         where (p.field_regex is null or lower(coalesce(i->>'field', '')) ~ p.field_regex) and lower(i::text) ~ p.regex
        union all
        select i::text from jsonb_array_elements(case when jsonb_typeof(r.payload->'notes') = 'array' then r.payload->'notes' else '[]' end) i
         where p.field_regex is null and lower(i::text) ~ p.regex) x
    )
    select (select count(distinct registry_id) from hit), (select count(*) from rev),
      (select jsonb_agg(distinct jsonb_build_object('firm', firm, 'fix', left(t, 300))) from (select * from hit order by id limit 2) h)
      into nf, nr, ex;
    update feedback_patterns set last_firms = nf, last_reviewed = nr, examples = coalesce(ex, examples), updated_at = now() where key = p.key;
    if nf >= p.threshold then
      msg := left(p.rule || ' Seen in ' || nf || ' of ' || nr || ' firms reviewed. Examples: ' ||
        coalesce((select string_agg((e->>'firm') || ': ' || (e->>'fix'), ' | ') from jsonb_array_elements(ex) e), ''), 2000);
      if p.feedback_id is not null and exists (select 1 from bot_feedback where id = p.feedback_id) then
        update bot_feedback set message = msg, active = true where id = p.feedback_id;
      else
        insert into bot_feedback(bot_id, message) values (p.bot_prefix, msg) returning id into fid;
        update feedback_patterns set feedback_id = fid, activated_at = now(), baseline_firms = nf, baseline_reviewed = nr where key = p.key;
      end if;
    end if;
    out := out || jsonb_build_object('key', p.key, 'firms', nf, 'reviewed', nr);
  end loop;
  return out;
end $$;
revoke all on function public.refresh_feedback_patterns() from public, anon, authenticated;

-- before/after: share of reviewed friend submissions with the pattern, split at the moment the feedback went live
create or replace view public.feedback_pattern_stats as
  select key, rule, threshold, feedback_id, activated_at, baseline_firms, baseline_reviewed,
    round(baseline_firms::numeric / nullif(baseline_reviewed, 0), 3) baseline_rate, last_firms, last_reviewed,
    round(last_firms::numeric / nullif(last_reviewed, 0), 3) current_rate, examples
  from feedback_patterns;
revoke all on public.feedback_pattern_stats from anon, authenticated, public;

-- 12. ingest RPC: resolve the firm, store raw, return per-item verdicts. The AFTER INSERT trigger promotes.
create or replace function public.research_enrich(p_bot text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare fid uuid; reg text := nullif(p_payload->>'registry_id', ''); slg text := nullif(p_payload->>'slug', ''); eid bigint;
  acc int; rej int; errs jsonb; v boolean;
begin
  if slg is not null then select id into fid from firms where slug = slg and deleted_at is null; end if;
  if fid is null and reg is not null then
    select id, slug into fid, slg from firms where deleted_at is null and not coalesce(is_test, false) and _firm_queue_id(id) = reg
     order by published desc limit 1;
  end if;
  if fid is null and reg is null then return jsonb_build_object('error', 'unknown firm: send "slug" (page slug) or "registry_id"'); end if;
  if reg is null then reg := _firm_queue_id(fid); end if;
  select count(*) filter (where ok), count(*) filter (where not ok),
    coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'section', section, 'field', field, 'item', left(txt, 120), 'url', url, 'reason', reason)) filter (where not ok), '[]')
    into acc, rej, errs from enrichment_items(p_payload);
  v := acc > 0;
  insert into research_enrichments(bot_id, registry_id, slug, firm_id, payload, valid, errors, accepted, rejected)
  values (p_bot, reg, slg, fid, p_payload, v, errs, acc, rej) returning id into eid;
  return jsonb_build_object('enrichment_id', eid, 'firm', slg, 'registry_id', reg, 'on_page', fid is not null, 'valid', v,
    'accepted_items', acc, 'rejected_items', rej, 'rejected', errs);
end $$;
revoke all on function public.research_enrich(text, jsonb) from public, anon, authenticated;
grant execute on function public.research_enrich(text, jsonb) to service_role;

create or replace function public._enrichment_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.valid then
    if new.firm_id is not null then perform promote_enrichment(new.firm_id); end if;
    perform search_log_from_enrichment(new.id);
    perform refresh_feedback_patterns();
  end if;
  return null;
end $$;
drop trigger if exists enrichment_promote on public.research_enrichments;
create trigger enrichment_promote after insert on public.research_enrichments for each row execute function public._enrichment_after_insert();

-- friend submissions keep feeding the search log too
create or replace function public._submission_search_log() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin perform search_log_from_submission(new.id);
  exception when others then raise warning 'search_log_from_submission(%) failed: %', new.id, sqlerrm; end;
  return null;
end $$;
drop trigger if exists submission_search_log on public.research_submissions;
create trigger submission_search_log after insert on public.research_submissions for each row execute function public._submission_search_log();

-- backfill the search log from existing valid friend submissions (raw rows are only read)
select search_log_from_submission(id) from public.research_submissions where valid;

-- lock down: internal functions are service-role only
revoke all on function public.search_log_from_enrichment(bigint), public.search_log_from_submission(bigint),
  public._enrich_cite(uuid, text, uuid, text, text) from public, anon, authenticated;
