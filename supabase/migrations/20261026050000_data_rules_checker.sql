-- THE RULE (docs/DATA_RULES.md), approved by Alex 2026-10-25 7:27 PM PT, for all bots and all data kinds:
-- bots send one structured item per fact into staging; free text only as a marked note. A single checker at publish
-- (checked_items + promote_enrichment, and promote_bot_facts for research_submissions) validates type and shape per section,
-- adds sources to an existing page row instead of duplicating it, flags conflicts instead of overwriting, never publishes
-- notes, and records every verdict with a reason in publish_checks (returned to the bot).
-- Existing data is NOT changed here: enrichments received before this migration keep the old promotion
-- (_promote_enrichment_legacy) until the cleanup step sets ingest_settings.data_rules_from_enrichment_id lower and re-promotes.

create table if not exists public.publish_checks (
  id bigserial primary key,
  origin text not null check (origin in ('enrichment', 'submission')),
  origin_id bigint,
  bot_id text,
  firm_id uuid,
  section text,
  kind text,
  field text,
  item jsonb,
  outcome text not null check (outcome in ('published', 'merged', 'conflict', 'rejected', 'note')),
  reason text,
  target_table text,
  target_id uuid,
  created_at timestamptz not null default now());
create index if not exists publish_checks_origin on public.publish_checks(origin, origin_id);
create index if not exists publish_checks_firm on public.publish_checks(firm_id);
alter table public.publish_checks enable row level security;
revoke all on public.publish_checks from public, anon, authenticated;
grant select, insert, update, delete on public.publish_checks to service_role;
grant usage on sequence public.publish_checks_id_seq to service_role;

insert into public.ingest_settings(key, value)
select 'data_rules_from_enrichment_id', (coalesce(max(id), 0) + 1)::text from public.research_enrichments
on conflict (key) do nothing;

create or replace function public._rules_cutoff() returns bigint language sql stable set search_path = public as $$
  select coalesce((select value::bigint from ingest_settings where key = 'data_rules_from_enrichment_id' and value ~ '^\d+$'), 0) $$;

-- Why a piece of text cannot be shown as a fact (null = fine).
create or replace function public._note_text(t text, maxlen int default 300) returns text language sql immutable as $$
  select case
    when t is null or btrim(t) = '' then null
    when t ~* '(\mbot [a-z ]*records?\M|schedule [a-d] (individuals|lists)|related persons?:|\mmatch(es)? an? (schedule|surname|fund)|\(log entry|no source url|\[the 10 checks\]|\msearched\M.*\mfound\M)'
      then 'looks like a research note (bookkeeping text), not a fact: send it as {"note": "..."}'
    when t ~* '(https?://|www\.)' then 'URL inside the text: put the link in "source" and keep only the fact in the text'
    when length(t) > maxlen then 'text is over ' || maxlen || ' characters: send one fact per item'
  end $$;

-- Why a string cannot be one person's name (null = fine).
create or replace function public._person_name_bad(n text) returns text language sql immutable as $$
  select case
    when n is null or btrim(n) = '' then 'person needs "name"'
    when _note_text(n, 80) is not null then 'name: ' || _note_text(n, 80)
    when n ~ '[0-9;:|/()\[\]]' or n ~* '\s(and|&)\s' or n ~* ',(?!\s*(jr|sr|ii|iii|iv)\.?\s*$)'
      then 'name must be one person''s name only (no lists, numbers or brackets)'
    when array_length(regexp_split_to_array(btrim(n), '\s+'), 1) > 6 then 'name must be one person''s name only (more than 6 words)'
  end $$;

create or replace function public._norm_txt(t text) returns text language sql immutable as $$
  select regexp_replace(lower(coalesce(t, '')), '[^a-z0-9]', '', 'g') $$;

create or replace function public._section_key(k text) returns text language sql immutable as $$
  select case k when 'Overview' then 'overview' when 'The 10 checks' then 'checks' when 'Legal & regulatory' then 'legal'
    when 'People & board seats' then 'people' when 'Funds' then 'funds' when 'Timeline' then 'timeline'
    when 'Press coverage' then 'press' when 'What founders say' then 'founders' when 'Limited partners' then 'lps' else lower(k) end $$;

create or replace function public._section_fields(s text) returns text language sql immutable as $$
  select case s
    when 'people' then '{"name", "role", "kind": officer|board|move, "company" (board seats), "since", "source"}'
    when 'funds' then '{"name", "amount", "currency", "date", "source"}'
    when 'overview' then '{"label", "value", "source"}'
    when 'lps' then '{"name", "type", "source"}'
    when 'legal' then '{"title", "date", "status", "allegation": true|false, "source"}'
    when 'timeline' then '{"date", "event", "source"}'
    when 'press' then '{"outlet", "date", "headline", "url", "snippet"}'
    when 'founders' then '{"who", "quote", "date", "source"}'
    else 'a structured object' end $$;

-- Source + section check shared by every item (null = fine).
create or replace function public._src_reason(url text, sec text) returns text language sql stable set search_path = public as $$
  select case
    when nullif(btrim(coalesce(url, '')), '') is null then 'no source URL'
    when url !~* '^https?://[^\s/]+\.[^\s]+$' then 'source is not a URL'
    when not _enrich_src_ok(url) then 'source not allowed (.gov/.mil other than SEC and courts, or a search/chat page)'
    when sec is null or sec not in ('people', 'funds', 'overview', 'lps', 'legal', 'timeline', 'press', 'founders') then 'field has no page section (kept raw only)'
  end $$;

-- THE checker: one item (an object) for one section -> {outcome: ok|note|rejected, reason, f: normalised fields}.
create or replace function public._check_item(sec text, knd text, fld text, i jsonb, url text) returns jsonb
language plpgsql stable set search_path = public as $$
declare f jsonb := '{}'; e text[] := '{}'; a text; b text; c text; d text; x text;
  dt constant text := '^\d{4}(-\d{2}(-\d{2})?)?$';
begin
  if jsonb_typeof(i) is distinct from 'object' then
    return jsonb_build_object('outcome', 'rejected', 'reason', 'each item must be an object: ' || _section_fields(sec));
  end if;
  if i ? 'note' or i->>'type' = 'note' then
    return jsonb_build_object('outcome', 'note', 'reason', 'note kept internal (never published)', 'f', jsonb_build_object('note', left(coalesce(i->>'note', i->>'item'), 4000)));
  end if;
  if _src_reason(url, sec) is not null then return jsonb_build_object('outcome', 'rejected', 'reason', _src_reason(url, sec)); end if;
  if i ? 'item' and not (i ?| array['name', 'person', 'label', 'title', 'event', 'headline', 'quote']) then
    return jsonb_build_object('outcome', 'rejected', 'reason', 'free text ("item") is refused: send ' || _section_fields(sec) || ' or mark it {"note": "..."}');
  end if;
  if sec = 'people' then
    a := nullif(btrim(coalesce(i->>'name', i->>'person')), ''); b := nullif(btrim(coalesce(i->>'role', i->>'title')), '');
    c := lower(coalesce(nullif(btrim(i->>'kind'), ''), case when lower(coalesce(fld, '')) ~ '^board' then 'board' else 'officer' end));
    d := nullif(btrim(i->>'since'), ''); x := nullif(btrim(i->>'company'), '');
    if _person_name_bad(a) is not null then e := e || _person_name_bad(a); end if;
    if b is null then e := e || 'person needs "role"'::text; elsif _note_text(b, 120) is not null then e := e || ('role: ' || _note_text(b, 120)); end if;
    if c not in ('officer', 'board', 'move') then e := e || '"kind" must be officer, board or move'::text; end if;
    if d is not null and d !~ dt then e := e || '"since" must be a date (YYYY, YYYY-MM or YYYY-MM-DD)'::text; end if;
    if x is not null and _note_text(x, 120) is not null then e := e || ('company: ' || _note_text(x, 120)); end if;
    f := jsonb_build_object('name', a, 'role', b, 'kind', c, 'since', d, 'company', x);
  elsif sec = 'funds' then
    a := nullif(btrim(coalesce(i->>'name', i->>'fund')), ''); d := nullif(btrim(i->>'date'), ''); x := upper(coalesce(nullif(btrim(i->>'currency'), ''), 'USD'));
    if a is null then e := e || 'fund needs "name"'::text; elsif _note_text(a, 150) is not null then e := e || ('name: ' || _note_text(a, 150)); end if;
    if i ? 'amount' and i->>'amount' is not null and coalesce(i->>'amount', '') !~ '^\d+(\.\d+)?$' then e := e || '"amount" must be a number in full units (e.g. 250000000)'::text; end if;
    if x !~ '^[A-Z]{3}$' then e := e || '"currency" must be a 3-letter code'::text; end if;
    if d is not null and d !~ dt then e := e || '"date" must be YYYY, YYYY-MM or YYYY-MM-DD'::text; end if;
    f := jsonb_build_object('name', a, 'amount', case when i->>'amount' ~ '^\d+(\.\d+)?$' then (i->>'amount')::numeric end, 'currency', x, 'date', d);
  elsif sec = 'overview' then
    a := nullif(btrim(i->>'label'), ''); b := nullif(btrim(coalesce(i->>'value', i->>'title')), '');
    if a is null then e := e || 'overview fact needs "label"'::text; elsif _note_text(a, 40) is not null then e := e || ('label: ' || _note_text(a, 40)); end if;
    if b is null then e := e || 'overview fact needs "value"'::text; elsif _note_text(b, 300) is not null then e := e || ('value: ' || _note_text(b, 300)); end if;
    f := jsonb_build_object('label', a, 'value', b);
  elsif sec = 'lps' then
    a := nullif(btrim(coalesce(i->>'name', i->>'lp_name')), ''); b := nullif(btrim(coalesce(i->>'type', i->>'lp_type')), '');
    if a is null then e := e || 'LP needs "name"'::text; elsif _note_text(a, 200) is not null then e := e || ('name: ' || _note_text(a, 200)); end if;
    if b is not null and _note_text(b, 40) is not null then e := e || ('type: ' || _note_text(b, 40)); end if;
    f := jsonb_build_object('name', a, 'type', b);
  elsif sec = 'legal' then
    a := nullif(btrim(i->>'title'), ''); d := nullif(btrim(i->>'date'), ''); b := nullif(btrim(i->>'status'), '');
    if a is null then e := e || 'legal item needs "title"'::text; elsif _note_text(a, 200) is not null then e := e || ('title: ' || _note_text(a, 200)); end if;
    if d is not null and d !~ dt then e := e || '"date" must be YYYY, YYYY-MM or YYYY-MM-DD'::text; end if;
    if b is not null and _note_text(b, 40) is not null then e := e || ('status: ' || _note_text(b, 40)); end if;
    f := jsonb_build_object('title', a, 'date', d, 'status', b,
      'allegation', knd = 'lead' or coalesce(i->>'allegation', '') in ('true', 't', '1'));
  elsif sec = 'timeline' then
    a := nullif(btrim(coalesce(i->>'event', i->>'title')), ''); d := nullif(btrim(i->>'date'), '');
    if d is null or d !~ dt then e := e || 'timeline item needs "date" (YYYY, YYYY-MM or YYYY-MM-DD)'::text; end if;
    if a is null then e := e || 'timeline item needs "event"'::text; elsif _note_text(a, 200) is not null then e := e || ('event: ' || _note_text(a, 200)); end if;
    f := jsonb_build_object('date', d, 'event', a);
  elsif sec = 'press' then
    a := nullif(btrim(i->>'headline'), ''); b := nullif(btrim(i->>'outlet'), ''); c := nullif(btrim(i->>'snippet'), ''); d := nullif(btrim(i->>'date'), '');
    if a is null or b is null then e := e || 'press item needs outlet + headline + url'::text; end if;
    if a is not null and _note_text(a, 300) is not null then e := e || ('headline: ' || _note_text(a, 300)); end if;
    if c is not null and _note_text(c, 600) is not null then e := e || ('snippet: ' || _note_text(c, 600)); end if;
    f := jsonb_build_object('outlet', b, 'headline', a, 'snippet', c, 'date', d);
  elsif sec = 'founders' then
    a := nullif(btrim(i->>'who'), ''); b := nullif(btrim(i->>'quote'), ''); d := nullif(btrim(i->>'date'), '');
    if a is null then e := e || 'founder quote needs "who"'::text; elsif _note_text(a, 160) is not null then e := e || ('who: ' || _note_text(a, 160)); end if;
    if b is null then e := e || 'founder quote needs "quote"'::text; elsif _note_text(b, 600) is not null then e := e || ('quote: ' || _note_text(b, 600)); end if;
    f := jsonb_build_object('who', a, 'quote', b, 'date', d, 'outlet', nullif(btrim(i->>'outlet'), ''));
  end if;
  if cardinality(e) > 0 then
    return jsonb_build_object('outcome', 'rejected', 'reason', array_to_string(e, '; ') || ' (format: ' || _section_fields(sec) || ')');
  end if;
  return jsonb_build_object('outcome', 'ok', 'f', jsonb_strip_nulls(f));
end $$;

-- Every item of an enrichment payload with its verdict. Replaces enrichment_items for enrichments under the rule.
create or replace function public.checked_items(p jsonb)
returns table(n int, kind text, section text, field text, item jsonb, url text, f jsonb, outcome text, reason text)
language plpgsql stable set search_path = public as $$
declare s record; i jsonb; g text; v jsonb; r jsonb; lbl text; t text;
begin
  n := 0;
  for s in select x.key k, x.value val from jsonb_each(case when jsonb_typeof(p->'sections') = 'object' then p->'sections' else '{}' end) x loop
    for i in select y from jsonb_array_elements(case when jsonb_typeof(s.val) = 'array' then s.val else '[]' end) y loop
      n := n + 1; kind := 'section'; section := _section_key(s.k); field := null; item := i;
      url := case when jsonb_typeof(i) = 'object' then coalesce(i->>'source', i->>'url', i->>'source_url') end;
      r := _check_item(section, 'section', null, i, url);
      f := r->'f'; outcome := r->>'outcome'; reason := r->>'reason';
      return next;
    end loop;
  end loop;
  foreach g in array array['add', 'fix', 'lead'] loop
    for i in select y from jsonb_array_elements(case when jsonb_typeof(p->(case g when 'lead' then 'leads' else g end)) = 'array'
                                                 then p->(case g when 'lead' then 'leads' else g end) else '[]' end) y loop
      n := n + 1; kind := g; item := i; field := i->>'field'; section := _enrich_section(field);
      url := coalesce(i->>'source_url', i->>'source', i->>'url');
      v := case when g = 'fix' then coalesce(i->'correct_value', i->'value') else i->'value' end;
      f := null; reason := null;
      if jsonb_typeof(i) is distinct from 'object' then
        outcome := 'rejected'; reason := 'each entry must be an object {field, value, source_url}';
      elsif jsonb_typeof(v) = 'object' then
        r := _check_item(section, g, field, v || jsonb_build_object('source', url), url);
        f := r->'f'; outcome := r->>'outcome'; reason := r->>'reason';
      else
        t := btrim(v #>> '{}');
        if _src_reason(url, section) is not null then
          outcome := 'rejected'; reason := _src_reason(url, section);
        elsif nullif(t, '') is null then
          outcome := 'rejected'; reason := 'empty item';
        elsif g = 'fix' and section = 'people' and field ~ '\[[^\]]+\]' then
          reason := _note_text(t, 200);
          outcome := case when reason is null then 'ok' else 'rejected' end;
          f := jsonb_build_object('person', substring(field from '\[([^\]]+)\]'), 'value', t);
        elsif section in ('overview', 'funds') and lower(field) !~ '^(funds|limitedpartners|limited_partners|lps)' then
          lbl := case when lower(field) ~ '^hq' then 'Headquarters' when lower(field) ~ '^founded' then 'Founded'
                      when lower(field) ~ '^(aum|facts\.aum)' then 'Regulatory AUM' when lower(field) ~ '^legal_entities' then 'Legal entity'
                      when lower(field) ~ '^website' then 'Website' else initcap(replace(split_part(field, '.', 1), '_', ' ')) end;
          reason := coalesce(_note_text(t, 300), case when lower(field) ~ '^(aum|facts\.aum)' and g <> 'lead' and t !~ '\d' then 'AUM needs a numeric figure' end);
          outcome := case when reason is null then 'ok' else 'rejected' end;
          f := jsonb_build_object('label', lbl, 'value', t, 'scalar', true);
        else
          outcome := 'rejected'; reason := 'value must be an object: ' || _section_fields(section) || ' (or mark free text {"note": "..."})';
        end if;
      end if;
      return next;
    end loop;
  end loop;
end $$;

-- The pre-rule promotion, unchanged, for enrichments received before the rule (until the cleanup step).
CREATE OR REPLACE FUNCTION public._promote_enrichment_legacy(p_firm uuid)
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
      continue;
    end if;
    n := n + 1;
  end loop;
  select coalesce(jsonb_object_agg(table_name, c), '{}') into cnt from (select table_name, count(*) c from enrichment_rows where firm_id = p_firm group by 1) x;
  perform _apply_name_only(p_firm);
  return cnt || jsonb_build_object('promoted', n, 'enrichment_id', e.id);
end $function$
;
revoke all on function public._promote_enrichment_legacy(uuid) from public, anon, authenticated;

create or replace function public._pc(p_eid bigint, p_bot text, p_firm uuid, p_sec text, p_kind text, p_field text, p_item jsonb,
  p_outcome text, p_reason text, p_table text, p_id uuid)
returns void language sql security definer set search_path = public as $$
  insert into publish_checks(origin, origin_id, bot_id, firm_id, section, kind, field, item, outcome, reason, target_table, target_id)
  values ('enrichment', p_eid, p_bot, p_firm, p_sec, p_kind, p_field, p_item, p_outcome, p_reason, p_table, p_id) $$;

-- Cite a source on an existing page row (dedupe) and remember it so a later promotion removes only what it added.
create or replace function public._enrich_cite_merge(p_firm uuid, p_type text, p_id uuid, p_url text, p_date text, p_eid bigint)
returns void language plpgsql security definer set search_path = public as $$
declare fs uuid := md5(p_type || ':' || p_id || ':' || p_url)::uuid;
begin
  if exists (select 1 from fact_sources x join sources s on s.id = x.source_id where x.fact_type = p_type and x.fact_id = p_id and s.url = p_url) then return; end if;
  perform _enrich_cite(p_firm, p_type, p_id, p_url, p_date);
  insert into enrichment_rows values (p_firm, 'fact_sources', fs, p_eid) on conflict do nothing;
end $$;

create or replace function public.promote_enrichment(p_firm uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e research_enrichments; it record; f firms; rid uuid; xid uuid; xv text; n int := 0; cnt jsonb;
  chk text := to_char(now() at time zone 'America/Los_Angeles', 'Mon FMDD, YYYY');
  t_t text; t_id uuid; t_c text; person text; v text; lbl text; tbl text; badge text; lead boolean;
begin
  select * into f from firms where id = p_firm;
  if f.id is null then return '{}'; end if;
  select * into e from research_enrichments where firm_id = p_firm and valid order by received_at desc, id desc limit 1;
  if e.id is null or e.id < _rules_cutoff() then return _promote_enrichment_legacy(p_firm); end if;
  -- remove what earlier enrichments put on this page (rows, their sources, sources added to existing rows)
  delete from fact_sources x using enrichment_rows r where r.firm_id = p_firm and r.table_name = 'fact_sources' and x.id = r.row_id;
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
  delete from publish_checks where origin = 'enrichment' and origin_id = e.id and outcome in ('published', 'merged', 'conflict');
  insert into firm_owned_media(firm_id, host, path, label, origin)
  select p_firm, _dom(u), coalesce(rtrim(substring(lower(u) from '://[^/]+(/[^?#]*)'), '/'), ''), nullif(o->>'label', ''), 'enricher'
    from jsonb_array_elements(case when jsonb_typeof(e.payload->'owned_media') = 'array' then e.payload->'owned_media' else '[]' end) o,
         lateral (select case jsonb_typeof(o) when 'string' then o #>> '{}' else coalesce(o->>'url', o->>'source') end u) z
   where _dom(u) is not null
  on conflict do nothing;

  for it in select * from checked_items(e.payload) c where c.outcome = 'ok' order by c.n loop
    rid := md5('enrich:' || p_firm || ':' || it.kind || ':' || it.section || ':' || coalesce(it.field, '') || ':' || it.f::text || ':' || it.url)::uuid;
    lead := it.kind = 'lead';
    badge := case it.kind when 'fix' then 'Correction' when 'lead' then 'Lead (unverified)' end;
    xid := null; xv := null;

    if it.kind = 'fix' then
      t_t := null; t_id := null; t_c := null;
      person := coalesce(it.f->>'person', it.f->>'name');
      v := coalesce(it.f->>'value', it.f->>'role');
      if it.section = 'people' and person is not null then
        select 'firm_people_roles', id, 'role' into t_t, t_id, t_c from firm_people_roles
         where firm_id = p_firm and not hidden and _norm_txt(person_name) = _norm_txt(person) order by sort_order limit 1;
      elsif lower(it.field) ~ '^(aum|facts\.aum)' then
        select 'firm_profile_facts', id, 'value' into t_t, t_id, t_c from firm_profile_facts
         where firm_id = p_firm and hero_label in ('Assets', 'Regulatory AUM', 'AUM') order by origin nulls first limit 1;
      elsif lower(it.field) = 'hq' then
        select 'firm_profile_facts', id, 'value' into t_t, t_id, t_c from firm_profile_facts
         where firm_id = p_firm and hero_label = 'HQ' order by origin nulls first limit 1;
      end if;
      insert into firm_corrections(id, firm_id, registry_id, enrichment_id, field, record_id, bot_value, correct_value, source_url, target_table, target_id, target_col)
      values (rid, p_firm, e.registry_id, e.id, it.field, it.item->>'record_id', it.item->>'bot_value', left(v, 1000), it.url, t_t, t_id, t_c)
      on conflict (id) do update set active = true, enrichment_id = excluded.enrichment_id, target_table = excluded.target_table,
        target_id = excluded.target_id, target_col = excluded.target_col;
      perform _enrich_cite(p_firm, 'firm_corrections', rid, it.url, chk);
      insert into enrichment_rows values (p_firm, 'firm_corrections', rid, e.id) on conflict do nothing;
      if t_id is not null then
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'published', 'correction shown over the existing row (row itself unchanged)', t_t, t_id); n := n + 1; continue;
      end if;
      if it.section = 'people' then
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'rejected', 'fix names a person who is not on the page: send them as "add" with {name, role, source}', null, null); continue;
      end if;
    end if;

    if it.section = 'people' then
      v := (it.f->>'role') || coalesce(', ' || (it.f->>'company'), '') || coalesce(' (since ' || (it.f->>'since') || ')', '');
      select id, role into xid, xv from firm_people_roles
       where firm_id = p_firm and not hidden and kind = it.f->>'kind' and _norm_txt(person_name) = _norm_txt(it.f->>'name')
       order by _norm_txt(role) = _norm_txt(v) desc, sort_order limit 1;
      if xid is not null and (_norm_txt(xv) = _norm_txt(v) or coalesce(xv, '') = '' or position(_norm_txt(it.f->>'role') in _norm_txt(xv)) > 0) then
        perform _enrich_cite_merge(p_firm, 'firm_people_roles', xid, it.url, chk, e.id);
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'merged', 'already on the page: source added', 'firm_people_roles', xid);
      elsif xid is not null and it.f->>'kind' = 'officer' then
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'conflict', format('page lists %s as "%s"; bot says "%s" (not overwritten; send a fix with a source if the page is wrong)', it.f->>'name', xv, v), 'firm_people_roles', xid);
      else
        insert into firm_people_roles(id, firm_id, kind, person_name, role, badge, sort_order)
        values (rid, p_firm, it.f->>'kind', left(it.f->>'name', 120), left(v, 300), badge, 500 + it.n) on conflict (id) do nothing;
        perform _enrich_cite(p_firm, 'firm_people_roles', rid, it.url, chk);
        insert into enrichment_rows values (p_firm, 'firm_people_roles', rid, e.id) on conflict do nothing;
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'published', null, 'firm_people_roles', rid);
      end if;

    elsif it.section in ('overview', 'funds', 'lps') then
      if it.section = 'funds' and not coalesce((it.f->>'scalar')::boolean, false) then
        v := concat_ws(' · ', it.f->>'name',
               case when it.f ? 'amount' then case when it.f->>'currency' = 'USD' then _promo_money(jsonb_build_object('amount_usd', (it.f->>'amount')::numeric))
                                                   else (it.f->>'amount') || ' ' || (it.f->>'currency') end end,
               it.f->>'date');
        lbl := 'Funds';
        select id, value into xid, xv from firm_profile_facts
         where firm_id = p_firm and section = 'funds' and (_norm_txt(value) = _norm_txt(v) or _norm_txt(split_part(value, ' · ', 1)) = _norm_txt(it.f->>'name'))
         order by _norm_txt(value) = _norm_txt(v) desc limit 1;
      elsif it.section = 'lps' then
        v := (it.f->>'name') || coalesce(' (' || (it.f->>'type') || ')', ''); lbl := 'Limited partners';
        select id, value into xid, xv from firm_profile_facts
         where firm_id = p_firm and section = 'lps' and _norm_txt(split_part(value, ' (', 1)) = _norm_txt(it.f->>'name') limit 1;
      else
        v := it.f->>'value'; lbl := it.f->>'label';
        select id, value into xid, xv from firm_profile_facts
         where firm_id = p_firm and section = it.section and (_norm_txt(value) = _norm_txt(v)
               or (_norm_txt(coalesce(label, hero_label)) = _norm_txt(lbl) and lbl in ('Headquarters', 'Founded', 'Regulatory AUM')))
         order by _norm_txt(value) = _norm_txt(v) desc limit 1;
      end if;
      if lead then lbl := 'Lead (unverified)'; elsif it.kind = 'fix' then lbl := 'Correction'; end if;
      if xid is not null and _norm_txt(xv) = _norm_txt(v) then
        perform _enrich_cite_merge(p_firm, 'firm_profile_facts', xid, it.url, chk, e.id);
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'merged', 'already on the page: source added', 'firm_profile_facts', xid);
      elsif xid is not null and not lead and it.kind <> 'fix' then
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'conflict', format('page says "%s"; bot says "%s" (not overwritten; send a fix with a source if the page is wrong)', xv, v), 'firm_profile_facts', xid);
      else
        insert into firm_profile_facts(id, firm_id, section, label, value, sort_order, origin)
        values (rid, p_firm, it.section, lbl, left(v, 400), 500 + it.n, 'enricher submission ' || e.id) on conflict (id) do nothing;
        perform _enrich_cite(p_firm, 'firm_profile_facts', rid, it.url, chk);
        insert into enrichment_rows values (p_firm, 'firm_profile_facts', rid, e.id) on conflict do nothing;
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'published', null, 'firm_profile_facts', rid);
      end if;

    elsif it.section = 'legal' then
      lead := lead or coalesce((it.f->>'allegation')::boolean, false);
      v := case when lead then 'Lead (allegation, not verified): ' || (it.f->>'title') when it.kind = 'fix' then 'Correction: ' || (it.f->>'title') else it.f->>'title' end;
      select id into xid from firm_legal_items where firm_id = p_firm and _norm_txt(regexp_replace(title, '^(Lead \(allegation, not verified\)|Correction): ', '')) = _norm_txt(it.f->>'title') limit 1;
      if xid is not null then
        perform _enrich_cite_merge(p_firm, 'firm_legal_items', xid, it.url, chk, e.id);
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'merged', 'already on the page: source added', 'firm_legal_items', xid);
      else
        insert into firm_legal_items(id, firm_id, grp, title, year_label, state, status_label, tone, note, sort_order)
        values (rid, p_firm,
          case when _dom(it.url) ~ '(courtlistener\.com|uscourts\.gov|pacer\.gov|justia\.com|law360\.com|casetext\.com)$' then 'case'
               when _dom(it.url) ~ '(sec\.gov|finra\.org|fca\.org\.uk)$' then 'regulator' else 'context' end,
          left(v, 300), coalesce(substring(it.f->>'date' from '^(\d{4})'), substring(it.f->>'title' from '((19|20)\d{2})')),
          case when lead then 'Unverified' when coalesce(it.f->>'status', it.f->>'title') ~* '(dismissed|terminated|settled|closed|judgment|vacated)' then 'Closed' end,
          case when lead then 'Lead · allegation' else it.f->>'status' end, null, null, 500 + it.n) on conflict (id) do nothing;
        perform _enrich_cite(p_firm, 'firm_legal_items', rid, it.url, chk);
        insert into enrichment_rows values (p_firm, 'firm_legal_items', rid, e.id) on conflict do nothing;
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'published', null, 'firm_legal_items', rid);
      end if;

    elsif it.section = 'timeline' then
      select id into xid from timeline_events where firm_id = p_firm and date_label = it.f->>'date' and _norm_txt(body) = _norm_txt(it.f->>'event') limit 1;
      if xid is not null then
        perform _enrich_cite_merge(p_firm, 'timeline_events', xid, it.url, chk, e.id);
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'merged', 'already on the page: source added', 'timeline_events', xid);
      else
        insert into timeline_events(id, firm_id, date_label, kind, body, sort_order)
        values (rid, p_firm, it.f->>'date', case when lead then 'Lead (unverified)' else 'Reported' end, left(it.f->>'event', 300),
          500 - coalesce(substring(it.f->>'date' from '^(\d{4})')::int - 1900, 0)) on conflict (id) do nothing;
        perform _enrich_cite(p_firm, 'timeline_events', rid, it.url, chk);
        insert into enrichment_rows values (p_firm, 'timeline_events', rid, e.id) on conflict do nothing;
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'published', null, 'timeline_events', rid);
      end if;

    elsif it.section = 'founders' then
      select id into xid from founder_accounts where firm_id = p_firm and url = it.url and _norm_txt(snippet) = _norm_txt(it.f->>'quote') limit 1;
      if xid is not null then
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'merged', 'already on the page', 'founder_accounts', xid);
      else
        insert into founder_accounts(id, firm_id, outlet, date_label, headline, url, snippet, sort_order, independent)
        values (rid, p_firm, coalesce(it.f->>'outlet', source_label(_dom(it.url), it.url)),
          coalesce(it.f->>'date', substring(it.f->>'who' from '(\d{4}-\d{2}-\d{2})')),
          left(it.f->>'who', 300), it.url, left(it.f->>'quote', 600), 500 + it.n, not _own_media(p_firm, it.url))
        on conflict (id) do nothing;
        perform _enrich_cite(p_firm, 'founder_accounts', rid, it.url, chk);
        insert into enrichment_rows values (p_firm, 'founder_accounts', rid, e.id) on conflict do nothing;
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'published', null, 'founder_accounts', rid);
      end if;

    elsif it.section = 'press' then
      select id into rid from press_items where url = it.url order by created_at limit 1;
      if rid is null then
        rid := md5('enrich-press:' || it.url)::uuid;
        insert into press_items(id, publisher, domain, url, published_on, published_label, headline, snippet, data_status, retrieved_at, source_system)
        values (rid, coalesce(it.f->>'outlet', source_label(_dom(it.url), it.url)), _dom(it.url), it.url,
          case when it.f->>'date' ~ '^\d{4}-\d{2}-\d{2}$' then (it.f->>'date')::date end, it.f->>'date',
          left(it.f->>'headline', 400), left(it.f->>'snippet', 600), 'real', now(), 'enricher') on conflict (id) do nothing;
      end if;
      if exists (select 1 from press_item_firms where press_item_id = rid and firm_id = p_firm) then
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'merged', 'already on the page', 'press_items', rid);
      else
        insert into press_item_firms(press_item_id, firm_id, sort_order) values (rid, p_firm, 500 + it.n);
        insert into enrichment_rows values (p_firm, 'press_item_firms', rid, e.id) on conflict do nothing;
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'published', null, 'press_items', rid);
      end if;
    else
      continue;
    end if;
    n := n + 1;
  end loop;
  select coalesce(jsonb_object_agg(table_name, c), '{}') into cnt from (select table_name, count(*) c from enrichment_rows where firm_id = p_firm group by 1) x;
  perform _apply_name_only(p_firm);
  return cnt || jsonb_build_object('promoted', n, 'enrichment_id', e.id, 'rule', 'data-rules');
end $$;
revoke all on function public.promote_enrichment(uuid) from public, anon, authenticated;
grant execute on function public.promote_enrichment(uuid) to service_role;
revoke all on function public._pc(bigint, text, uuid, text, text, text, jsonb, text, text, text, uuid) from public, anon, authenticated;

-- Ingest: every item gets a verdict from the checker; rejects and notes are stored with their reason and returned to the bot,
-- with what was published, merged into an existing row (source added) or flagged as a conflict.
create or replace function public.research_enrich(p_bot text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare fid uuid; reg text := nullif(p_payload->>'registry_id', ''); slg text := nullif(p_payload->>'slug', ''); page text; eid bigint;
  acc int; rej int; nts int; errs jsonb; v boolean; pub jsonb;
begin
  if slg is not null then select id into fid from firms where slug = slg and deleted_at is null; end if;
  if fid is null and reg is not null then
    select id into fid from firms where deleted_at is null and not coalesce(is_test, false) and registry_id = _registry_target(reg)
     order by published desc limit 1;
    if fid is null and exists (select 1 from research_queue where registry_id = reg) then
      fid := ensure_firm_for_registry(reg, false);
    end if;
  end if;
  if fid is null and reg is null then return jsonb_build_object('error', 'unknown firm: send "slug" (page slug) or "registry_id"'); end if;
  if reg is null then reg := _firm_queue_id(fid); end if;
  select slug into page from firms where id = fid and published;
  select count(*) filter (where outcome = 'ok'), count(*) filter (where outcome = 'rejected'), count(*) filter (where outcome = 'note'),
    coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'section', section, 'field', field, 'item', left(item::text, 160), 'url', url, 'reason', reason))
      filter (where outcome = 'rejected'), '[]')
    into acc, rej, nts, errs from checked_items(p_payload);
  -- before the rule's cutoff (only possible while the setting is raised by hand) the old item check decides validity
  if (select coalesce(max(id), 0) + 1 from research_enrichments) < _rules_cutoff() then
    select count(*) filter (where ok), count(*) filter (where not ok),
      coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'section', section, 'field', field, 'item', left(txt, 160), 'url', url, 'reason', reason)) filter (where not ok), '[]')
      into acc, rej, errs from enrichment_items(p_payload);
    nts := 0;
  end if;
  v := acc > 0;
  insert into research_enrichments(bot_id, registry_id, slug, firm_id, payload, valid, errors, accepted, rejected)
  values (p_bot, reg, coalesce(slg, (select slug from firms where id = fid)), fid, p_payload, v, errs, acc, rej) returning id into eid;
  if eid >= _rules_cutoff() then
  insert into publish_checks(origin, origin_id, bot_id, firm_id, section, kind, field, item, outcome, reason)
  select 'enrichment', eid, p_bot, fid, section, kind, field, item, outcome, reason from checked_items(p_payload) where outcome in ('rejected', 'note');
  end if;
  select coalesce(jsonb_object_agg(outcome, c), '{}') into pub from (select outcome, count(*) c from publish_checks where origin = 'enrichment' and origin_id = eid group by 1) x;
  return jsonb_build_object('enrichment_id', eid, 'firm', coalesce(page, slg), 'registry_id', reg, 'on_page', page is not null, 'valid', v,
    'accepted_items', acc, 'rejected_items', rej, 'notes_kept', nts, 'rejected', errs, 'outcomes', pub,
    'conflicts', coalesce((select jsonb_agg(jsonb_build_object('section', section, 'item', left(item::text, 160), 'reason', reason))
                             from publish_checks where origin = 'enrichment' and origin_id = eid and outcome = 'conflict'), '[]'),
    'rules', 'docs/DATA_RULES.md: one structured item per fact; free text only as {"note": "..."}');
end $$;
revoke all on function public.research_enrich(text, jsonb) from public, anon, authenticated;
grant execute on function public.research_enrich(text, jsonb) to service_role;

-- Search log: under the rule, "found" rows come from the checker's accepted items.
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
        from enrichment_items(e.payload) where ok and e.id < _rules_cutoff()
        union all
        select case when section = 'people' and f->>'kind' = 'board' then 'board_seats' else section end, url
        from checked_items(e.payload) where outcome = 'ok' and e.id >= _rules_cutoff()) x
  group by sec, _dom(url);
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.search_log_from_enrichment(bigint) from public, anon, authenticated;

-- research_submissions publish path: same text rule; a note-like value is not shown and is recorded with its reason.
CREATE OR REPLACE FUNCTION public.promote_bot_facts(p_firm uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare qid text := _firm_queue_id(p_firm); k record; rec record; fid uuid; n int := 0;
  hv text; v text; hl text; src jsonb; sid uuid; i int;
begin
  if qid is null then return 0; end if;
  delete from publish_checks where origin = 'submission' and firm_id = p_firm and field in ('hq', 'aum');
  for k in select * from (values ('hq', 'overview', 'Headquarters', 'HQ', array['HQ'], 0),
                                 ('aum', 'funds', 'Assets under management', 'Assets', array['Assets', 'Regulatory AUM', 'AUM'], 0)) t(fp, sec, lbl, hl, same, so) loop
    -- never compete with a curated (non-promoted) card of the same kind
    continue when exists (select 1 from firm_profile_facts where firm_id = p_firm and hero_label = any(k.same) and origin is null);
    select s.id sub, r.value r into rec from research_submissions s, jsonb_array_elements(coalesce(s.payload->'records', '[]')) r
     where s.registry_id = qid and s.valid and r->>'field_path' = k.fp
       and exists (select 1 from jsonb_array_elements(public._rec_sources(s.id, r)) x where coalesce(x->>'url', '') like 'http%' and public._promo_src_ok(x->>'url'))
     order by s.received_at desc, s.id desc limit 1;
    fid := md5('promoted:' || p_firm || ':' || k.fp)::uuid;
    if rec.sub is null then delete from firm_profile_facts where id = fid and origin like 'promoted from submission %' and origin is not null; delete from fact_sources where fact_type = 'firm_profile_facts' and fact_id = fid and not exists (select 1 from firm_profile_facts where id = fid); continue; end if;
    hl := k.hl;
    if k.fp = 'hq' then
      hv := coalesce(rec.r->'value'->>'city', rec.r->>'value'); v := coalesce(rec.r->'value'->>'address', hv);
    else
      hv := case when jsonb_typeof(rec.r->'value'->'amount_usd') = 'number' then _promo_money(rec.r->'value')
                 when jsonb_typeof(rec.r->'value'->'raum_usd') = 'number' then _promo_money(jsonb_build_object('amount_usd', rec.r->'value'->'raum_usd')) end;
      if jsonb_typeof(rec.r->'value'->'amount_usd') is distinct from 'number' and jsonb_typeof(rec.r->'value'->'raum_usd') = 'number' then hl := 'Regulatory AUM'; end if;  -- press_aum text has no cited URL: hide
      v := hv || coalesce(' · ' || (rec.r->'value'->>'basis'), '');
    end if;
    if _note_text(v, 400) is not null or _note_text(hv, 60) is not null then
      insert into publish_checks(origin, origin_id, firm_id, section, kind, field, item, outcome, reason)
      values ('submission', rec.sub, p_firm, k.sec, 'record', k.fp, rec.r, 'rejected', coalesce(_note_text(v, 400), _note_text(hv, 60)));
      hv := null;
    end if;
    if nullif(trim(hv), '') is null then delete from firm_profile_facts where id = fid and origin like 'promoted from submission %' and origin is not null; delete from fact_sources where fact_type = 'firm_profile_facts' and fact_id = fid and not exists (select 1 from firm_profile_facts where id = fid); continue; end if;
    insert into firm_profile_facts(id, firm_id, section, label, value, hero_label, hero_value, sort_order, origin)
    values (fid, p_firm, k.sec, k.lbl, left(v, 400), hl, left(hv, 60), k.so, 'promoted from submission ' || rec.sub)
    on conflict (id) do update set value = excluded.value, hero_label = excluded.hero_label, hero_value = excluded.hero_value, origin = excluded.origin
      where firm_profile_facts.origin like 'promoted from submission %';
    delete from fact_sources where fact_type = 'firm_profile_facts' and fact_id = fid;
    i := 0;
    for src in select x from jsonb_array_elements(public._rec_sources(rec.sub, rec.r)) x where coalesce(x->>'url', '') like 'http%' and public._promo_src_ok(x->>'url') loop
      insert into sources(url, domain, publisher, retrieved_at, data_status, source_system)
      values (src->>'url', substring(src->>'url' from '://(?:www\.)?([^/]+)'), substring(src->>'url' from '://(?:www\.)?([^/]+)'),
              coalesce((src->>'retrieved_at')::timestamptz, now()), 'real', 'bot_promotion')
      on conflict (url) do nothing;
      select id into sid from sources where url = src->>'url';
      insert into fact_sources(id, source_id, firm_id, fact_type, fact_id, label, date_label, sort_order, data_status)
      values (md5(fid || ':' || (src->>'url'))::uuid, sid, p_firm, 'firm_profile_facts', fid,
              substring(src->>'url' from '://(?:www\.)?([^/]+)'), src->>'retrieved_at', i, 'real')
      on conflict (id) do nothing;
      i := i + 1;
    end loop;
    n := n + 1;
  end loop;
  return n;
end $function$;
