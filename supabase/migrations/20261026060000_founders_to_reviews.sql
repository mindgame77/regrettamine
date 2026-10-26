-- Founders quotes ("What founders say") now go to reviews, shown in Activity.
-- * both publish paths (legacy + promote_enrichment) write a review instead of a founder_accounts card,
--   deduped per firm on the source url (or same quote), sources merged; re-promote no longer deletes old cards.
-- * founder_accounts gets moved_to_review: a card mapped into reviews is hidden from the old section.
--   Cards are hidden one by one (per firm data move), the section and renderer stay for firms not moved yet.
alter table public.founder_accounts add column if not exists moved_to_review uuid references public.reviews(id);

create or replace function public._founder_review(p_firm uuid, p_who text, p_quote text, p_url text, p_date text, p_outlet text)
returns table(rid uuid, merged boolean) language plpgsql security definer set search_path = public as $$
declare own boolean := _own_media(p_firm, p_url); has_url boolean := coalesce(p_url, '') ~ '^https?://';
  d text := substring(coalesce(p_date, '') || ' ' || coalesce(p_who, '') from '(\d{4}-\d{2}-\d{2})');
  y text := substring(coalesce(p_date, '') from '(\d{4})'); k text;
begin
  k := case when has_url then 'url:' || lower(regexp_replace(p_url, '^https?://(www\.)?|/+$', '', 'g'))
            else 'quote:' || md5(_norm_txt(p_quote)) end;
  select r.id into rid from reviews r where r.firm_id = p_firm
    and (r.dedupe_key = k or (has_url and p_url = any(r.source_urls)) or (_norm_txt(r.body) = _norm_txt(p_quote) and coalesce(p_quote, '') <> ''))
    order by r.created_at limit 1;
  if rid is not null then
    update reviews set source_urls = (select array_agg(distinct u) from unnest(coalesce(source_urls, '{}') || case when has_url then array[p_url] else '{}'::text[] end) u),
      updated_at = now() where id = rid;
    merged := true; return next; return;
  end if;
  rid := md5('founder-review:' || p_firm || ':' || k)::uuid;
  insert into reviews(id, firm_id, body, first_hand, verification_status, moderation_status, reviewed_on, anonymous, role_label,
      date_precision, author_name, source_urls, review_type, independent, is_public, dedupe_key, source_system)
  values (rid, p_firm, left(p_quote, 2000), false, 'unverified',
      case when has_url and not own then 'approved' else 'pending' end,
      coalesce(d::date, case when y is not null then make_date(y::int, 1, 1) end), false, left(p_who, 300),
      case when d is not null then 'day' when y is not null then 'year' else 'unknown' end,
      left(split_part(coalesce(p_who, ''), ',', 1), 200), case when has_url then array[p_url] else '{}' end,
      case when own then 'firm_voice' else 'founder' end, not own, has_url and not own, k, 'enricher')
  on conflict (id) do nothing;
  merged := false; return next;
end $$;
revoke all on function public._founder_review(uuid, text, text, text, text, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public._sec_items(p_key text, p_firm uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
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
    select jsonb_build_object('head', p.headline, 'outlet', source_label(p.publisher, p.url) || case when _own_media(p_firm, p.url) then ' · Own media' else '' end, 'independent', not _own_media(p_firm, p.url), 'date', p.published_label, 'url', p.url, 'snippet', p.snippet, 'logo', p.logo_path, 'group', p.group_label,
        'src', jsonb_build_array(jsonb_build_object('label', source_label(p.publisher, p.url), 'date', p.published_label, 'url', p.url))), pf.sort_order
      from press_items p join press_item_firms pf on pf.press_item_id = p.id
      where pf.firm_id = p_firm and p_key = 'press' and p.data_status = 'real' and p.url <> ''
    union all
    select jsonb_build_object('head', headline, 'outlet', regexp_replace(outlet, ' · firm-owned, not independent$', '') || case when ind then '' else ' · Own media' end, 'independent', ind, 'date', date_label, 'url', url, 'snippet', snippet, 'src', _src('founder_accounts', id)), sort_order
      from (select *, independent and not _own_media(p_firm, url) ind from founder_accounts where firm_id = p_firm and p_key = 'founders' and moved_to_review is null) fa
    union all
    select jsonb_build_object('head', person_name, 'kind', kind, 'role', coalesce(_ovr('firm_people_roles', id, 'role'), role),
        'badge', case when _ovr('firm_people_roles', id, 'role') is not null then 'Corrected' else badge end,
        'src', _src('firm_people_roles', id) || _ovr_src('firm_people_roles', id)),
        case kind when 'board' then 0 when 'move' then 1000 else 2000 end + sort_order
      from firm_people_roles where firm_id = p_firm and p_key = 'people' and not hidden
    union all
    select jsonb_build_object('head', date_label || ' · ' || body, 'date', date_label, 'kind', kind, 'body', body, 'src', _src('timeline_events', id)), sort_order
      from timeline_events where firm_id = p_firm and p_key = 'timeline'
  ) x where p_key in ('checks', 'press') or jsonb_array_length(it->'src') > 0
$function$;

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

create or replace function public.promote_enrichment(p_firm uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare lead_m boolean; e research_enrichments; it record; f firms; rid uuid; xid uuid; xv text; n int := 0; cnt jsonb;
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
