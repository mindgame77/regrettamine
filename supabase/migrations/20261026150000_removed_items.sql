-- STEP 2 (Alex, Oct 26 2026): a removed-items list so cleaned-up items are never re-added.
--  removed_items: firm, section, text fingerprint (+ word set), case-number and source-URL fingerprints, reason, who, when.
--  Every promote path (promote_enrichment, _promote_enrichment_legacy, promote_bot_facts) refuses an item that
--  matches and logs it as 'rejected' in publish_checks.
--  Fingerprint: lowercase; drop Lead/Correction prefixes, URLs, dates, punctuation and quotes; collapse spaces.
--  Match (same firm): same section and same fingerprint or >= 75% word overlap; OR a shared case number;
--  OR same section + same source URL (press: URL alone; other sections also need >= 50% word overlap,
--  so a shared filing page such as an SEC adviser summary does not block every fact cited to it).
--  record_removed(): call before deleting or hiding a row in a future cleanup; it records the reason and locks the row id.
--  One-time load from cleanup_backup: every row a batch deleted, plus people rows now hidden.

create table if not exists public.removed_items (
  id bigint generated always as identity primary key,
  firm_id uuid not null,
  section text not null,
  text_fp text not null,
  words text[] not null default '{}',
  case_fps text[] not null default '{}',
  url_fps text[] not null default '{}',
  reason text not null,
  removed_by text not null,
  removed_at timestamptz not null default now(),
  source_table text,
  source_row_id uuid,
  sample text
);
create unique index if not exists removed_items_row on public.removed_items (source_table, source_row_id, firm_id) where source_row_id is not null;
create index if not exists removed_items_firm on public.removed_items (firm_id, section);
alter table public.removed_items enable row level security;
revoke all on public.removed_items from anon, authenticated;

create or replace function public._fp_text(t text) returns text language sql immutable as $$
  select btrim(regexp_replace(
    regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
      lower(coalesce(t, '')),
      '^\s*((lead|correction)(\s*\([^)]*\))?\s*:\s*)+', ''),                         -- Lead (allegation, not verified): / Correction:
      'https?://\S+', ' ', 'g'),                                                        -- urls
      '\m\d{4}-\d{1,2}-\d{1,2}\M|\m\d{1,2}/\d{1,2}/\d{2,4}\M|\m\d{1,2}/\d{4}\M', ' ', 'g'), -- numeric dates
      '\m(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?(\s+\d{1,2}(st|nd|rd|th)?,?)?', ' ', 'g'), -- month names
      '\m(19|20)\d{2}\M', ' ', 'g'),                                                    -- years
      '[''"‘’“”`]', '', 'g'),                                                           -- quotes
    '[^a-z0-9]+', ' ', 'g'));
$$;
create or replace function public._fp_words(fp text) returns text[] language sql immutable as $$
  select coalesce(array_agg(distinct w order by w), '{}') from unnest(string_to_array(coalesce(fp, ''), ' ')) w where length(w) > 1;
$$;
create or replace function public._fp_cases(t text) returns text[] language sql immutable as $$
  select coalesce(array_agg(distinct coalesce(m[1], m[2])), '{}')
    from regexp_matches(lower(coalesce(t, '')), '(?:\m\d{1,2}:)?(\d{2}-[a-z]{2,4}-\d{3,6})\M|\m(\d{2}-\d{5})\M', 'g') m;
$$;
create or replace function public._fp_url(u text) returns text language sql immutable as $$
  select nullif(rtrim(regexp_replace(regexp_replace(regexp_replace(lower(btrim(coalesce(u, ''))), '^https?://(www\.)?', ''), '#.*$', ''),
                                     '([?&])utm_[^&]*', '\1', 'g'), '/?&'), '');
$$;
create or replace function public._jaccard(a text[], b text[]) returns numeric language sql immutable as $$
  select case when coalesce(cardinality(a), 0) = 0 or coalesce(cardinality(b), 0) = 0 then 0
    else (select count(*) from (select unnest(a) intersect select unnest(b)) i)::numeric
       / (select count(*) from (select unnest(a) union select unnest(b)) u) end;
$$;

-- returns a rejection reason when the item matches a removed item for this firm, else null
create or replace function public._removed_match(p_firm uuid, p_section text, p_text text, p_urls text[] default null)
returns text language plpgsql stable set search_path to 'public' as $$
declare fp text := _fp_text(p_text); w text[]; c text[] := _fp_cases(p_text); u text[]; r removed_items;
begin
  if p_firm is null then return null; end if;
  w := _fp_words(fp);
  u := coalesce((select array_agg(_fp_url(x)) from unnest(p_urls) x where _fp_url(x) is not null), '{}');
  select * into r from removed_items x
   where x.firm_id = p_firm
     and ((x.section = p_section and ((fp <> '' and x.text_fp = fp) or _jaccard(x.words, w) >= 0.75))
       or (cardinality(c) > 0 and x.case_fps && c)
       or (x.section = p_section and cardinality(u) > 0 and x.url_fps && u and (p_section = 'press' or _jaccard(x.words, w) >= 0.5)))
   order by x.id limit 1;
  if r.id is null then return null; end if;
  return format('matches removed item #%s (%s): not re-added', r.id, r.reason);
end $$;

create or replace function public._removed_add(p_firm uuid, p_table text, p_row_id uuid, p_row jsonb, p_urls text[],
                                               p_reason text, p_who text, p_when timestamptz default now())
returns bigint language plpgsql set search_path to 'public' as $$
declare sec text; txt text; urls text[] := p_urls; rid bigint;
begin
  if p_table = 'firm_profile_facts' then sec := coalesce(p_row->>'section', 'overview'); txt := p_row->>'value';
  elsif p_table = 'firm_legal_items' then sec := 'legal'; txt := p_row->>'title';
  elsif p_table = 'firm_people_roles' then sec := 'people'; txt := concat_ws(' ', p_row->>'person_name', p_row->>'role');
  elsif p_table = 'timeline_events' then sec := 'timeline'; txt := p_row->>'body';
  elsif p_table = 'press_item_firms' then sec := 'press';
    select coalesce(p.headline, ''), array_append(coalesce(urls, '{}'), p.url) into txt, urls from press_items p where p.id = p_row_id;
  else raise exception 'record_removed: unsupported table %', p_table;
  end if;
  insert into removed_items(firm_id, section, text_fp, words, case_fps, url_fps, reason, removed_by, removed_at, source_table, source_row_id, sample)
  values (p_firm, sec, _fp_text(txt), _fp_words(_fp_text(txt)), _fp_cases(txt),
          coalesce((select array_agg(distinct _fp_url(x)) from unnest(urls) x where _fp_url(x) is not null), '{}'),
          p_reason, p_who, coalesce(p_when, now()), p_table, p_row_id, left(txt, 200))
  on conflict (source_table, source_row_id, firm_id) where source_row_id is not null do nothing
  returning id into rid;
  return rid;
end $$;

-- helper for future cleanups: call BEFORE deleting or hiding the row. Records why, and locks the row id.
create or replace function public.record_removed(p_table text, p_row_id uuid, p_firm uuid, p_reason text, p_who text default 'cleanup')
returns bigint language plpgsql security definer set search_path to 'public' as $$
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
  return rid;
end $$;

revoke execute on function public._removed_match(uuid, text, text, text[]), public._removed_add(uuid, text, uuid, jsonb, text[], text, text, timestamptz),
  public.record_removed(text, uuid, uuid, text, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.promote_enrichment(p_firm uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare lead_m boolean; e research_enrichments; it record; f firms; rid uuid; xid uuid; xv text; n int := 0; cnt jsonb;
  chk text := to_char(now() at time zone 'America/Los_Angeles', 'Mon FMDD, YYYY');
  t_t text; t_id uuid; t_c text; person text; v text; lbl text; tbl text; badge text; lead boolean;
begin
  select * into f from firms where id = p_firm;
  if f.id is null then return '{}'; end if;
  select * into e from research_enrichments where firm_id = p_firm and valid order by received_at desc, id desc limit 1;
  if e.id is null or e.id < _rules_cutoff() then return _promote_enrichment_legacy(p_firm); end if;
  delete from publish_checks where origin = 'enrichment' and origin_id = e.id and outcome in ('published', 'merged', 'conflict');
  insert into firm_owned_media(firm_id, host, path, label, origin)
  select p_firm, _dom(u), coalesce(rtrim(substring(lower(u) from '://[^/]+(/[^?#]*)'), '/'), ''), nullif(o->>'label', ''), 'enricher'
    from jsonb_array_elements(case when jsonb_typeof(e.payload->'owned_media') = 'array' then e.payload->'owned_media' else '[]' end) o,
         lateral (select case jsonb_typeof(o) when 'string' then o #>> '{}' else coalesce(o->>'url', o->>'source') end u) z
   where _dom(u) is not null
  on conflict do nothing;

  for it in select * from checked_items(e.payload) c where c.outcome = 'ok' order by c.n loop
    rid := md5('enrich:' || p_firm || ':' || it.kind || ':' || it.section || ':' || coalesce(it.field, '') || ':' || it.f::text || ':' || it.url)::uuid;
    if _is_locked_any(rid, p_firm) then
      perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'rejected', 'removed or locked by a cleanup: not re-added', null, rid); continue;
    end if;
    xv := _removed_match(p_firm, it.section, concat_ws(' ', it.f->>'title', it.f->>'value', it.f->>'event', it.f->>'name', it.f->>'role', it.f->>'company', it.f->>'headline', it.f->>'snippet'), array[it.url]);
    if xv is not null then
      perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'rejected', xv, 'removed_items', null); continue;
    end if;
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
      if t_id is not null and _is_locked(t_t, t_id, p_firm) then
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'conflict', 'row is locked by a cleanup: correction not applied', t_t, t_id); continue;
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
        if not _is_locked('firm_people_roles', xid, p_firm) then perform _enrich_cite_merge(p_firm, 'firm_people_roles', xid, it.url, chk, e.id); end if;
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
        if not _is_locked('firm_profile_facts', xid, p_firm) then perform _enrich_cite_merge(p_firm, 'firm_profile_facts', xid, it.url, chk, e.id); end if;
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
        if not _is_locked('firm_legal_items', xid, p_firm) then perform _enrich_cite_merge(p_firm, 'firm_legal_items', xid, it.url, chk, e.id); end if;
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
        if not _is_locked('timeline_events', xid, p_firm) then perform _enrich_cite_merge(p_firm, 'timeline_events', xid, it.url, chk, e.id); end if;
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
      -- founder quotes go to reviews (Activity): one review per source url, sources merged; nothing new in founder_accounts
      select r.rid, r.merged into xid, lead_m from _founder_review(p_firm, it.f->>'who', it.f->>'quote', it.url, it.f->>'date', it.f->>'outlet') r;
      perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item,
        case when lead_m then 'merged' else 'published' end, case when lead_m then 'already in reviews' end, 'reviews', xid);

    elsif it.section = 'press' then
      select id into rid from press_items where url = it.url order by created_at limit 1;
      if rid is null then
        rid := md5('enrich-press:' || it.url)::uuid;
        insert into press_items(id, publisher, domain, url, published_on, published_label, headline, snippet, data_status, retrieved_at, source_system)
        values (rid, coalesce(it.f->>'outlet', source_label(_dom(it.url), it.url)), _dom(it.url), it.url,
          case when it.f->>'date' ~ '^\d{4}-\d{2}-\d{2}$' then (it.f->>'date')::date end, it.f->>'date',
          left(it.f->>'headline', 400), left(it.f->>'snippet', 600), 'real', now(), 'enricher') on conflict (id) do nothing;
      end if;
      if _is_locked('press_item_firms', rid, p_firm) then
        perform _pc(e.id, e.bot_id, p_firm, it.section, it.kind, it.field, it.item, 'rejected', 'removed or locked by a cleanup: not re-added', 'press_items', rid);
      elsif exists (select 1 from press_item_firms where press_item_id = rid and firm_id = p_firm) then
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
    if _note_text(v, 400) is not null or _note_text(hv, 60) is not null then
      insert into publish_checks(origin, origin_id, firm_id, section, kind, field, item, outcome, reason)
      values ('submission', rec.sub, p_firm, k.sec, 'record', k.fp, rec.r, 'rejected', coalesce(_note_text(v, 400), _note_text(hv, 60)));
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

-- one-time load from past cleanups (idempotent): rows a batch deleted, and people rows a batch hid
do $load$ begin
  if to_regclass('public.cleanup_backup') is null then return; end if;
  perform _removed_add(b.firm_id, b.table_name, b.row_id, b.row_data,
           (select array_agg(distinct s.url) from cleanup_backup c join sources s on s.id = (c.row_data->>'source_id')::uuid
             where c.table_name = 'fact_sources' and c.row_data->>'fact_id' = b.row_id::text),
           case when b.gone then 'removed in cleanup batch ' else 'hidden in cleanup batch ' end || b.batch,
           'cleanup (Alex approved)', b.saved_at)
    from (select distinct on (x.table_name, x.row_id, x.firm_id) x.*,
                 case x.table_name
                   when 'firm_profile_facts' then not exists (select 1 from firm_profile_facts y where y.id = x.row_id)
                   when 'firm_legal_items' then not exists (select 1 from firm_legal_items y where y.id = x.row_id)
                   when 'firm_people_roles' then not exists (select 1 from firm_people_roles y where y.id = x.row_id)
                   when 'timeline_events' then not exists (select 1 from timeline_events y where y.id = x.row_id)
                   when 'press_item_firms' then not exists (select 1 from press_item_firms y where y.press_item_id = x.row_id and y.firm_id = x.firm_id)
                 end gone,
                 x.table_name = 'firm_people_roles' and exists (select 1 from firm_people_roles y where y.id = x.row_id and y.hidden) hid
            from cleanup_backup x
           where x.table_name in ('firm_profile_facts', 'firm_legal_items', 'firm_people_roles', 'timeline_events', 'press_item_firms')
             and x.row_id is not null and x.firm_id is not null
           order by x.table_name, x.row_id, x.firm_id, x.saved_at) b
   where b.gone or b.hid;
end $load$;
