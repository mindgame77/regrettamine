-- Step 4: docs/DATA_RULES.md as automatic checks inside every promote path, before an item is added.
-- One rule function, _data_rule(), is called from the existing checker (checked_items -> promote_enrichment / research_enrich),
-- from _promote_enrichment_legacy and from promote_bot_facts. A failing item stays in the holding area and is logged in
-- publish_checks as 'rejected' with the rule and reason. Duplicates keep the existing rule: merged into the page row, never a 2nd row.
-- data_rules_report() runs the same rule over the live page rows (read-only).

-- Why an item breaks a data rule ("rule: reason"), or null. f holds the item's fields (label/value/title/event/name/role/
-- company/headline/status/date/since/allegation); url is its source link.
create or replace function public._data_rule(sec text, knd text, f jsonb, url text) returns text
language plpgsql immutable set search_path = public as $$
declare txt text; d text; n text; single constant text := '^\d{4}(-\d{2}(-\d{2})?)?$'; x text;
begin
  f := coalesce(f, '{}');
  txt := concat_ws(' · ', f->>'label', f->>'value', f->>'title', f->>'event', f->>'name', f->>'role', f->>'company', f->>'headline', f->>'status');
  -- 1. every item has a source URL
  if coalesce(btrim(url), '') !~* '^https?://[^\s/]+\.[^\s]+$' then return 'source: no source URL'; end if;
  -- 2. leads and unverified allegations are never public
  if knd = 'lead' or coalesce(f->>'allegation', '') in ('true', 't', '1')
     or txt ~* '(^|[^a-z])lead\s*(\(|:|·)' or txt ~* '\m(not verified|unverified|allegation, not)\M' then
    return 'lead: leads and unverified allegations are never public (kept in the holding area)';
  end if;
  -- 3. no notes or research text as values
  if txt ~* '\m(searches? (were |was )?run|friend-?bot submission|awaiting review|research note|search log|no source url)' then
    return 'note: research text, not a fact (send it as {"note": "..."})';
  end if;
  foreach x in array array['label:40', 'value:300', 'title:200', 'event:300', 'role:120', 'company:120', 'headline:400'] loop
    n := f->>split_part(x, ':', 1);
    continue when n is null or (split_part(x, ':', 1) = 'value' and coalesce(f->>'label', '') ~* 'website|web site|url' and n ~* '^\s*(https?://|www\.)\S+\s*$');
    if _note_text(n, split_part(x, ':', 2)::int) is not null then
      return 'note: ' || split_part(x, ':', 1) || ' ' || _note_text(n, split_part(x, ':', 2)::int);
    end if;
  end loop;
  -- 4. dates: single YYYY / YYYY-MM / YYYY-MM-DD; timeline may also use a range; dates inside text are ignored
  d := nullif(btrim(coalesce(f->>'date', '')), '');
  if sec = 'timeline' then
    if d is null then return 'date: timeline item needs a date (YYYY, YYYY-MM, YYYY-MM-DD or a range)'; end if;
    if d !~ single and not (length(d) <= 40 and d ~ '\d{4}' and (d ~ '(–|—|/|\s-\s|\sto\s)' or d ~ '^\d{4}(-\d{2}){0,2}-\d{4}')) then
      return 'date: "' || left(d, 40) || '" is not YYYY, YYYY-MM, YYYY-MM-DD or a range';
    end if;
  elsif d is not null and d !~ single then
    return 'date: "' || left(d, 40) || '" is not YYYY, YYYY-MM or YYYY-MM-DD';
  end if;
  d := nullif(btrim(coalesce(f->>'since', '')), '');
  if d is not null and d !~ single then return 'date: "since" ' || left(d, 40) || ' is not YYYY, YYYY-MM or YYYY-MM-DD'; end if;
  -- 5. people rows are one real name, not a sentence or a list
  if sec = 'people' and f ? 'name' then
    n := btrim(coalesce(f->>'name', ''));
    if _person_name_bad(n) is not null then return 'person: ' || _person_name_bad(n); end if;
    if array_length(regexp_split_to_array(n, '\s+'), 1) > 3 and (n ~ '\.\s*$' or n ~* '\m(is|was|joined|has|had|left|served|serves|includes?)\M') then
      return 'person: name must be a real name, not a sentence';
    end if;
  end if;
  return null;
end $$;
revoke execute on function public._data_rule(text, text, jsonb, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public._check_item(sec text, knd text, fld text, i jsonb, url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
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
    if d is null or (d !~ dt and _data_rule('timeline', 'add', jsonb_build_object('date', d), 'https://date.check') is not null) then
      e := e || 'timeline item needs "date" (YYYY, YYYY-MM, YYYY-MM-DD or a range)'::text; end if;
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
end $function$;

CREATE OR REPLACE FUNCTION public.checked_items(p jsonb)
 RETURNS TABLE(n integer, kind text, section text, field text, item jsonb, url text, f jsonb, outcome text, reason text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare s record; i jsonb; g text; v jsonb; r jsonb; lbl text; t text;
begin
  n := 0;
  for s in select x.key k, x.value val from jsonb_each(case when jsonb_typeof(p->'sections') = 'object' then p->'sections' else '{}' end) x loop
    for i in select y from jsonb_array_elements(case when jsonb_typeof(s.val) = 'array' then s.val else '[]' end) y loop
      n := n + 1; kind := 'section'; section := _section_key(s.k); field := null; item := i;
      url := case when jsonb_typeof(i) = 'object' then coalesce(i->>'source', i->>'url', i->>'source_url') end;
      r := _check_item(section, 'section', null, i, url);
      f := r->'f'; outcome := r->>'outcome'; reason := r->>'reason';
      if outcome = 'ok' and _data_rule(section, kind, f, url) is not null then outcome := 'rejected'; reason := _data_rule(section, kind, f, url); end if;
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
      if outcome = 'ok' and _data_rule(section, kind, f, url) is not null then outcome := 'rejected'; reason := _data_rule(section, kind, f, url); end if;
      return next;
    end loop;
  end loop;
end $function$;

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
    continue when _is_locked_any(rid, p_firm);  -- removed or locked by a cleanup: never re-add or touch
    person := _removed_match(p_firm, it.section, it.txt, array[it.url]);
    if person is not null then
      perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, to_jsonb(it), 'rejected', person, 'removed_items', null); continue;
    end if;
    person := _data_rule(it.section, it.kind, case it.section
        when 'people' then jsonb_build_object('name', it.txt) when 'legal' then jsonb_build_object('title', it.txt)
        when 'timeline' then jsonb_build_object('event', it.txt, 'date', it.date_label)
        when 'press' then jsonb_build_object('headline', it.txt, 'date', it.date_label)
        when 'founders' then '{}'::jsonb else jsonb_build_object('value', it.txt) end, it.url);
    if person is not null then
      perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, to_jsonb(it), 'rejected', person, null, null); continue;
    end if;
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
      continue when t_id is not null and _is_locked(t_t, t_id, p_firm);  -- never correct over a locked row
      insert into firm_corrections(id, firm_id, registry_id, enrichment_id, field, record_id, bot_value, correct_value, source_url, target_table, target_id, target_col)
      values (rid, p_firm, e.registry_id, e.id, it.field, it.record_id, it.bot_value, left(it.txt, 1000), it.url, t_t, t_id, t_c)
      on conflict (id) do update set active = true, enrichment_id = excluded.enrichment_id, target_table = excluded.target_table,
        target_id = excluded.target_id, target_col = excluded.target_col;
      perform _enrich_cite(p_firm, 'firm_corrections', rid, it.url, chk);
      insert into enrichment_rows values (p_firm, 'firm_corrections', rid, e.id) on conflict do nothing;
      if t_id is not null then n := n + 1; continue; end if;
    end if;
    if it.section in ('overview', 'funds', 'lps') then
      continue when exists (select 1 from firm_profile_facts x where x.firm_id = p_firm and x.id <> rid and _norm_txt(x.value) = _norm_txt(left(it.txt, 600)));
      insert into firm_profile_facts(id, firm_id, section, label, value, sort_order, origin)
      values (rid, p_firm, it.section,
        case it.kind when 'fix' then 'Correction' when 'lead' then 'Lead (unverified)'
          else case it.section when 'overview' then 'Overview' when 'funds' then 'Funds' else 'Limited partners' end end,
        left(it.txt, 600), 500 + i, 'enricher submission ' || e.id) on conflict (id) do nothing;
      perform _enrich_cite(p_firm, 'firm_profile_facts', rid, it.url, chk);
      insert into enrichment_rows values (p_firm, 'firm_profile_facts', rid, e.id) on conflict do nothing;
    elsif it.section = 'legal' then
      continue when exists (select 1 from firm_legal_items x where x.firm_id = p_firm and x.id <> rid and strpos(_norm_txt(x.title), _norm_txt(left(it.txt, 600))) > 0);
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
      continue when exists (select 1 from firm_people_roles x where x.firm_id = p_firm and x.id <> rid and _norm_txt(x.person_name) = _norm_txt(left(it.txt, 600)));
      insert into firm_people_roles(id, firm_id, kind, person_name, role, badge, sort_order)
      values (rid, p_firm,
        case when it.txt ~* '\m(board|director)' then 'board' when it.txt ~* '\m(left|joined|former|depart|hired|promoted)' then 'move' else 'officer' end,
        left(it.txt, 600), '', case it.kind when 'fix' then 'Correction' when 'lead' then 'Lead (unverified)' end, 500 + i) on conflict (id) do nothing;
      perform _enrich_cite(p_firm, 'firm_people_roles', rid, it.url, chk);
      insert into enrichment_rows values (p_firm, 'firm_people_roles', rid, e.id) on conflict do nothing;
    elsif it.section = 'timeline' then
      continue when exists (select 1 from timeline_events x where x.firm_id = p_firm and x.id <> rid and _norm_txt(x.body) = _norm_txt(left(it.txt, 600)));
      insert into timeline_events(id, firm_id, date_label, kind, body, sort_order)
      values (rid, p_firm, coalesce(nullif(it.date_label, ''), 'Undated'), 'Reported', left(it.txt, 600),
        500 - coalesce(substring(it.date_label from '^(\d{4})')::int - 1900, 0)) on conflict (id) do nothing;
      perform _enrich_cite(p_firm, 'timeline_events', rid, it.url, chk);
      insert into enrichment_rows values (p_firm, 'timeline_events', rid, e.id) on conflict do nothing;
    elsif it.section = 'founders' then
      -- founder quotes go to reviews (Activity), not the old founders section
      perform _founder_review(p_firm, it.who, it.txt, it.url, it.date_label, it.outlet);
    elsif it.section = 'press' then
      select id into rid from press_items where url = it.url order by created_at limit 1;
      if rid is null then
        rid := md5('enrich-press:' || it.url)::uuid;
        insert into press_items(id, publisher, domain, url, published_on, published_label, headline, snippet, data_status, retrieved_at, source_system)
        values (rid, coalesce(nullif(it.outlet, ''), source_label(_dom(it.url), it.url)), _dom(it.url), it.url,
          case when it.date_label ~ '^\d{4}-\d{2}-\d{2}$' then it.date_label::date end, it.date_label,
          left(it.txt, 400), left(it.who, 600), 'real', now(), 'enricher') on conflict (id) do nothing;
      end if;
      if not exists (select 1 from press_item_firms where press_item_id = rid and firm_id = p_firm) and not _is_locked('press_item_firms', rid, p_firm) then
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
end $function$;

CREATE OR REPLACE FUNCTION public.promote_bot_facts(p_firm uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare qid text := _firm_queue_id(p_firm); k record; rec record; fid uuid; n int := 0;
  hv text; v text; xr text; hl text; src jsonb; sid uuid; i int;
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
    continue when _is_locked_any(fid, p_firm);  -- locked or removed by a cleanup
    if rec.sub is null then continue; /* add-only: never delete */ end if;
    hl := k.hl;
    if k.fp = 'hq' then
      hv := coalesce(rec.r->'value'->>'city', rec.r->>'value'); v := coalesce(rec.r->'value'->>'address', hv);
    else
      hv := case when jsonb_typeof(rec.r->'value'->'amount_usd') = 'number' then _promo_money(rec.r->'value')
                 when jsonb_typeof(rec.r->'value'->'raum_usd') = 'number' then _promo_money(jsonb_build_object('amount_usd', rec.r->'value'->'raum_usd')) end;
      if jsonb_typeof(rec.r->'value'->'amount_usd') is distinct from 'number' and jsonb_typeof(rec.r->'value'->'raum_usd') = 'number' then hl := 'Regulatory AUM'; end if;  -- press_aum text has no cited URL: hide
      v := hv || coalesce(' · ' || (rec.r->'value'->>'basis'), '');
    end if;
    xr := coalesce(_data_rule(k.sec, 'record', jsonb_build_object('label', k.lbl, 'value', v),
                   (select x->>'url' from jsonb_array_elements(public._rec_sources(rec.sub, rec.r)) x
                     where coalesce(x->>'url', '') like 'http%' and public._promo_src_ok(x->>'url') limit 1)),
                   _note_text(v, 400), _note_text(hv, 60));
    if rec.sub is not null and xr is not null then
      insert into publish_checks(origin, origin_id, firm_id, section, kind, field, item, outcome, reason)
      values ('submission', rec.sub, p_firm, k.sec, 'record', k.fp, rec.r, 'rejected', xr);
      hv := null;
    end if;
    if nullif(trim(hv), '') is null then continue; /* add-only: never delete */ end if;
    if _removed_match(p_firm, k.sec, v, null) is not null then
      insert into publish_checks(origin, origin_id, firm_id, section, kind, field, item, outcome, reason)
      values ('submission', rec.sub, p_firm, k.sec, 'record', k.fp, rec.r, 'rejected', _removed_match(p_firm, k.sec, v, null));
      continue;
    end if;
    insert into firm_profile_facts(id, firm_id, section, label, value, hero_label, hero_value, sort_order, origin)
    values (fid, p_firm, k.sec, k.lbl, left(v, 400), hl, left(hv, 60), k.so, 'promoted from submission ' || rec.sub)
    on conflict (id) do update set value = excluded.value, hero_label = excluded.hero_label, hero_value = excluded.hero_value, origin = excluded.origin
      where firm_profile_facts.origin like 'promoted from submission %';
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

-- Read-only: the same rule over every live (not hidden) page row of every firm, plus duplicates. Changes nothing.
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
      from press_item_firms pf join press_items p on p.id = pf.press_item_id where not pf.hidden
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
