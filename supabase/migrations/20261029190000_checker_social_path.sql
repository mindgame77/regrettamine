-- socialAccounts get their own Checker path (A2.10 / B3.8). Before this, they fell through to section "overview"
-- and failed on firm_profile_facts.label (not null), e.g. submissions 5352-5354 on 2026-10-29.
-- Linked from the firm's own site -> level-2 media_reach fact (like the #263 General Catalyst row).
-- Not linked -> skipped, published via _firm_social. The Checker report now carries a "reasons" list.
-- Rollback: supabase/rollbacks/20261029190000_checker_social_path.sql

create or replace function public._checker_social_platform(p text) returns text
language sql immutable set search_path to 'public' as $$
  select case lower(btrim(coalesce(p, ''))) when 'twitter' then 'x' when '' then null else lower(btrim(p)) end
$$;

create or replace function public._checker_social(p_firm uuid, p_f jsonb, p_url text)
returns table(lvl smallint, outcome text, reason text)
language plpgsql security definer set search_path to 'bots', 'public' as $$
declare acct text := public._checker_social_platform(p_f->>'platform'); u text := p_f->>'url';
begin
  if coalesce(p_f->>'linked_from_firm_site', '') <> 'true' then
    return query select null::smallint, 'skipped'::text, 'skipped, published via _firm_social'::text; return;
  end if;
  if acct is null or acct not in ('linkedin', 'x', 'youtube', 'instagram', 'tiktok') then
    return query select null::smallint, 'skipped'::text, ('skipped, platform ' || coalesce(acct, 'missing') || ' is not shown on the page')::text; return;
  end if;
  if u is null or u !~* '^https?://[^\s/]+\.[^\s]+$' then
    return query select null::smallint, 'failure'::text, 'social account needs url'::text; return;
  end if;
  if jsonb_typeof(p_f->'followers') is distinct from 'number' then
    return query select null::smallint, 'failure'::text, 'social followers must be a number'::text; return;
  end if;
  if exists (select 1 from vc_source_facts v where v.firm_id = p_firm and v.status = 'current' and v.fact_type = 'media_reach'
               and v.source_level = 2 and v.value->>'field' = 'media_' || acct || '_followers'
               and public._checker_url_key(coalesce(nullif(v.value->>'url', ''), v.source_url)) = public._checker_url_key(u)) then
    return query select 2::smallint, 'skipped'::text, 'already on the page, not re-checked'::text; return;
  end if;
  perform public._checker_write(p_firm, 'social', p_f, p_url, 2::smallint, null);
  return query select 2::smallint, 'published'::text, null::text;
end $$;

CREATE OR REPLACE FUNCTION public._checker_payload_items(p jsonb)
 RETURNS TABLE(n integer, section text, f jsonb, url text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_url text; v_dom text; v_date text;
begin
  if jsonb_typeof(p->'sections') = 'object' then
    return query select c.n, c.section, c.f, c.url from public.checked_items(p) c where c.outcome = 'ok';
  end if;
  if jsonb_typeof(p->'records') = 'array' then
    return query
    select s.n::int, s.section, s.f, s.url from (
      select row_number() over () n,
        case r->>'field_path'
          when 'people' then 'people' when 'peopleMoves' then 'people'
          when 'funds' then 'funds' when 'latestRaise' then 'funds'
          when 'limitedPartners' then 'lps' when 'portfolio' then 'deals'
          when 'lawsuits' then 'legal' when 'regulatoryActions' then 'legal'
          when 'sanctions' then 'legal' when 'controversies' then 'legal'
          when 'posts' then 'founders' when 'reviews' then 'founders'
          when 'socialAccounts' then 'social'
          else 'overview' end section,
        case when jsonb_typeof(r->'value') = 'object' then r->'value'
             else jsonb_build_object('label', r->>'field_path', 'value', r->>'value') end f,
        (select x->>'url' from jsonb_array_elements(case when jsonb_typeof(r->'sources') = 'array' then r->'sources' else '[]'::jsonb end) x limit 1) url
      from jsonb_array_elements(p->'records') r
    ) s;
  end if;
  v_url := coalesce(nullif(p->'firm'->>'website_source_url', ''), nullif(p->'firm'->>'website', ''),
    (select c->>'source_url' from jsonb_array_elements(case when jsonb_typeof(p->'coverage') = 'array' then p->'coverage' else '[]'::jsonb end) c
      where lower(coalesce(c->>'item', '')) in ('website', 'primary_domain') limit 1));
  v_dom := coalesce(nullif(p->'firm'->>'primary_domain', ''),
    (select c->>'value' from jsonb_array_elements(case when jsonb_typeof(p->'coverage') = 'array' then p->'coverage' else '[]'::jsonb end) c
      where lower(coalesce(c->>'item', '')) in ('website', 'primary_domain') limit 1),
    public._checker_host(v_url));
  v_date := (select c->>'retrieved_at' from jsonb_array_elements(case when jsonb_typeof(p->'coverage') = 'array' then p->'coverage' else '[]'::jsonb end) c
      where lower(coalesce(c->>'item', '')) in ('website', 'primary_domain') limit 1);
  if v_url is not null and public._checker_host(v_dom) is not null then
    return query select 0, 'overview'::text,
      jsonb_build_object('label', 'Website', 'value', public._checker_host(v_dom), 'date', v_date),
      v_url;
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public._checker_write(p_firm uuid, p_section text, p_f jsonb, p_url text, p_level smallint, p_check integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rid uuid := gen_random_uuid(); key text; n int := p_check; lab boolean := public._lab_firm(p_firm); acct text;
begin
  key := p_section || '|' || coalesce(nullif(p_url, ''), left(p_f::text, 200));
  if p_section = 'press' then
    insert into press_items(id, publisher, domain, url, published_label, headline, snippet, data_status, retrieved_at, source_system)
    values (rid, coalesce(p_f->>'outlet', public.source_label(public._dom(p_url), p_url)), public._dom(p_url), p_url,
            p_f->>'date', left(coalesce(p_f->>'headline', ''), 400), left(p_f->>'snippet', 600), 'real', now(), 'checker');
    insert into press_item_firms(press_item_id, firm_id, sort_order, check_mark, checked_on, checked_by, source_level)
    values (rid, p_firm, 900, 'checked_correct', case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif p_section = 'timeline' then
    insert into timeline_events(id, firm_id, date_label, kind, body, sort_order, source_url, check_mark, checked_on, checked_by, source_level)
    values (rid, p_firm, p_f->>'date', 'Reported', left(coalesce(p_f->>'event', ''), 300), 900, p_url, 'checked_correct',
            case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif p_section = 'people' then
    insert into firm_people_roles(id, firm_id, kind, person_name, role, sort_order, checked_on, checked_by, source_level)
    values (rid, p_firm, coalesce(p_f->>'kind', 'officer'), left(p_f->>'name', 120), left(coalesce(p_f->>'role', ''), 300), 900,
            case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif p_section = 'social' then
    -- socialAccounts (A2.10 / B3.8): a level-2 media_reach fact like the #263 General Catalyst row. Never firm_profile_facts.
    acct := public._checker_social_platform(p_f->>'platform');
    key := 'social|' || coalesce(p_f->>'url', '');
    insert into vc_source_facts(id, firm_id, fact_type, section, value, source_url, source_label, source_type, retrieved_at, data_status,
                                source_system, external_id, checked_on, checked_by, source_level)
    values (rid, p_firm, 'media_reach', 'media_reach',
            jsonb_build_object('field', 'media_' || acct || '_followers',
                               'value', (p_f->>'followers') || coalesce(' (@' || nullif(substring(p_f->>'url' from '^https?://[^/]+/(?:company/|@)?([^/?#]+)'), '') || ')', ''),
                               'url', p_f->>'url', 'entity', 'firm', 'publisher', initcap(acct),
                               'linked_from', coalesce(nullif(p_f->>'found_on_url', ''), p_url),
                               'linked_checked', coalesce(p_f->>'followers_read_at', to_char(now(), 'YYYY-MM-DD')),
                               'sheet_status', 'firm says'),
            p_f->>'url', initcap(acct), acct,
            coalesce((p_f->>'followers_read_at')::date::timestamptz, now()), 'real', 'checker',
            'checker:social:' || md5(p_firm::text || '|' || acct || '|' || public._checker_url_key(p_f->>'url')),
            case when lab then now() end, case when lab then 'Checker' end, 2);
  elsif p_section in ('overview', 'funds', 'lps') then
    insert into firm_profile_facts(id, firm_id, section, label, value, sort_order, origin, checked_on, checked_by, source_level)
    values (rid, p_firm, p_section,
            case p_section when 'overview' then p_f->>'label' when 'lps' then p_f->>'name' else 'Funds' end,
            left(case p_section when 'overview' then p_f->>'value' when 'lps' then p_f->>'name' else coalesce(p_f->>'name', '') end, 400),
            900, 'checker', case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif p_section = 'legal' then
    insert into firm_legal_items(id, firm_id, grp, title, year_label, status_label, sort_order, checked_on, checked_by, source_level)
    values (rid, p_firm, 'context', left(coalesce(p_f->>'title', ''), 300), substring(p_f->>'date' from '^(\d{4})'), p_f->>'status', 900,
            case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif p_section = 'founders' then
    insert into reviews(id, firm_id, body, first_hand, verification_status, moderation_status, anonymous, author_name, source_urls,
                        review_type, is_public, source_system, dedupe_key, checked_on, checked_by, source_level)
    values (rid, p_firm, left(coalesce(p_f->>'quote', ''), 2000), false, 'unverified', 'approved', false,
            left(p_f->>'who', 200), array[p_url], 'founder', true, 'checker', 'url:' || left(p_url, 400),
            case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
  elsif n is not null then
    insert into vc_source_facts(firm_id, fact_type, section, value, source_url, source_label, retrieved_at, data_status, source_system, external_id,
                                checked_on, checked_by, source_level)
    values (p_firm,
            case when n in (1, 2, 10) then 'sanctions_check' when n in (4, 5) then 'regulatory_record' when n = 8 then 'fund_fact' else 'legal_matter' end,
            'checks',
            jsonb_build_object('field', case n when 1 then 'sanctions' when 2 then 'terrorism_lists' when 3 then 'export_restrictions'
              when 4 then 'regulatory_action' when 5 then 'aml_penalties' when 7 then 'courts_worldwide' when 8 then 'registration_status'
              when 9 then 'people_screen' when 10 then 'pep' else 'legal_matter' end, 'value', left(p_f::text, 500)),
            p_url, 'Checker', now(), 'real', 'checker', 'checker:' || p_firm::text || ':' || n::text || ':' || md5(coalesce(p_url, '') || p_f::text),
            case when lab then now() end, case when lab then 'Checker' end, case when lab then p_level end);
    rid := gen_random_uuid();
  else
    return null;
  end if;
  insert into checker_marks(firm_id, kind, item_key, checked_by, source_level, url)
  values (p_firm, coalesce(p_section, 'check'), key, 'Checker', p_level, p_url)
  on conflict (firm_id, kind, item_key) do nothing;
  return rid;
end $function$;

CREATE OR REPLACE FUNCTION public.checker_publish_submission(p_id bigint, p_probes jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bots', 'public'
AS $function$
declare sub bots.research_submissions; fid uuid; it record; lvl smallint; ncheck int; outcome text; reason text;
  pub int := 0; skip int := 0; fail int := 0; unconf int := 0; merged int := 0; noted int := 0;
  probes jsonb; gate jsonb; host text; claimed text; opened boolean; website boolean;
  reasons jsonb := '[]'::jsonb;
begin
  select * into sub from research_submissions where id = p_id;
  if sub.id is null or not public._checker_publish_on() then
    return jsonb_build_object('ran', false);
  end if;
  -- Step B (A5.5): only rows the entry check Accepted; flagged links are opened first.
  gate := public._checker_entry_gate(sub.id, p_probes);
  if gate is not null then return gate; end if;
  select * into sub from research_submissions where id = p_id;
  select f.id into fid from firms f
   where f.deleted_at is null and f.registry_id = coalesce(public._registry_target(sub.registry_id), sub.registry_id)
   order by f.published desc limit 1;
  if fid is null or not public._lab_firm(fid) then
    return jsonb_build_object('ran', false, 'reason', 'not a lab firm');
  end if;
  probes := coalesce(p_probes, sub.payload->'probes');
  for it in select * from public._checker_payload_items(sub.payload) loop
    begin
      claimed := null;
      website := it.section = 'overview' and lower(coalesce(it.f->>'label', '')) in ('website', 'primary_domain');
      if website then
        host := public._dom(it.url);
        claimed := public._checker_host(it.f->>'value');
        if public.source_tier(it.url) is null then
          lvl := null; outcome := 'failure'; reason := 'link is not real (missing, not http, or a search/chat page)';
        elsif host is null or claimed is null or not (host = claimed or host like '%.' || claimed) then
          lvl := null; outcome := 'failure'; reason := 'link does not match the firm';
        else
          opened := public._checker_link_opens(it.url, probes);
          if opened is null then
            lvl := null; outcome := 'failure'; reason := 'link was not opened';
          elsif not opened then
            lvl := null; outcome := 'failure'; reason := 'link did not open';
          else
            lvl := 2; outcome := 'published'; reason := null;
          end if;
        end if;
      elsif it.section = 'social' then
        ncheck := null;
        select d.lvl, d.outcome, d.reason into lvl, outcome, reason from public._checker_social(fid, it.f, it.url) d;
      else
        ncheck := public._checker_check_n(it.section, it.url);
        select d.lvl, d.outcome, d.reason into lvl, outcome, reason
          from public._checker_decide(fid, it.section, it.f, it.url, ncheck, probes) d;
      end if;
      if outcome = 'published' and it.section <> 'social' then
        select p.outcome, p.reason into outcome, reason
          from public._checker_place(fid, it.section, it.f, it.url, lvl, ncheck, sub.id) p;
      end if;
      if website and outcome in ('published', 'merged', 'skipped') and claimed is not null then
        update firms set primary_domain = claimed
         where id = fid and (primary_domain is null or lower(primary_domain) = claimed);
      end if;
    exception when others then
      outcome := 'failure'; reason := sqlerrm;
    end;
    if outcome = 'published' then pub := pub + 1;
    elsif outcome = 'merged' then merged := merged + 1;
    elsif outcome = 'note' then noted := noted + 1;
    elsif outcome = 'skipped' then skip := skip + 1;
    elsif outcome = 'unconfirmed' then unconf := unconf + 1;
    else fail := fail + 1; end if;
    if outcome is distinct from 'published' and outcome is distinct from 'merged' then
      reasons := reasons || jsonb_build_array(jsonb_build_object('section', it.section, 'url', coalesce(it.f->>'url', it.url),
        'outcome', coalesce(outcome, 'failure'), 'reason', coalesce(reason, 'no reason given')));
    end if;
    if outcome in ('failure', 'unconfirmed') then
      insert into checker_holding(firm_id, origin, origin_id, kind, url, outcome, reason, item)
      values (fid, 'submission', sub.id, it.section, it.url,
              case when outcome = 'unconfirmed' then 'unconfirmed' else 'failure' end, reason, it.f);
    end if;
  end loop;
  return jsonb_build_object('ran', true, 'firm_id', fid, 'published', pub, 'merged', merged, 'note', noted,
    'skipped', skip, 'unconfirmed', unconf, 'failure', fail, 'reasons', reasons);
end $function$;

revoke all on function public._checker_social(uuid, jsonb, text) from public, anon, authenticated;
