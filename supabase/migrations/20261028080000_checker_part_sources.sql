-- Part-by-part source rules from docs/PAGE_DATA_GUIDE.md "Sources per page part".
-- The switch checker_publish stays false. This only changes how a dry run, or a later
-- flip, classifies an item. Existing rows are still not rewritten.

create or replace function public._host_is(p_url text, p_dom text) returns boolean
language sql immutable as $$
  select public._dom(p_url) = p_dom or public._dom(p_url) like '%.' || p_dom;
$$;

create or replace function public._known_outlet(p_url text) returns boolean
language sql immutable as $$
  select public._host_is(p_url, 'techcrunch.com') or public._host_is(p_url, 'reuters.com')
      or public._host_is(p_url, 'bloomberg.com') or public._host_is(p_url, 'axios.com')
      or public._host_is(p_url, 'ft.com') or public._host_is(p_url, 'wsj.com')
      or public._host_is(p_url, 'cnbc.com') or public._host_is(p_url, 'forbes.com')
      or public._host_is(p_url, 'theinformation.com');
$$;

create or replace function public._court_register(p_url text) returns boolean
language sql immutable as $$
  select public._host_is(p_url, 'courtlistener.com') or public._host_is(p_url, 'pacer.gov')
      or public._host_is(p_url, 'uscourts.gov');
$$;

create or replace function public._names_firm(p_firm uuid, p_text text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from firms f where f.id = p_firm and (
      (length(coalesce(f.name, '')) >= 3 and position(lower(f.name) in lower(coalesce(p_text, ''))) > 0)
      or (length(coalesce(f.short_name, '')) >= 2 and position(lower(f.short_name) in lower(coalesce(p_text, ''))) > 0)
      or (length(coalesce(f.display_name, '')) >= 3 and position(lower(f.display_name) in lower(coalesce(p_text, ''))) > 0)
    )
  );
$$;

-- Returns the level and whether the item is shown, held, or failed.
-- Amount and Lead on a deal are not filled here. The writer copies them only when the item already states them.
create or replace function public._checker_decide(
  p_firm uuid, p_section text, p_f jsonb, p_url text, p_check int, p_probes jsonb)
returns table(lvl smallint, outcome text, reason text)
language plpgsql stable security definer set search_path = public as $$
declare base smallint; blob text; who text; host text; firm_dom text; company_key text;
begin
  if public.source_tier(p_url) is null then
    lvl := null; outcome := 'failure'; reason := 'link is not real (missing, not http, or a search/chat page)';
    return next; return;
  end if;
  if p_probes is not null and (p_probes ? p_url) and (p_probes->>p_url) in ('false', 'f') then
    lvl := null; outcome := 'failure'; reason := 'dead link';
    return next; return;
  end if;
  if p_check is not null and p_url ~* 'opensanctions\.org' and p_check not in (1, 2, 10) then
    lvl := null; outcome := 'failure'; reason := 'OpenSanctions is only a source inside checks 1, 2 and 10';
    return next; return;
  end if;
  base := public._source_level(p_url, p_firm, p_check);
  blob := concat_ws(' ', p_f->>'headline', p_f->>'snippet', p_f->>'event', p_f->>'quote', p_f->>'title', p_f->>'value', p_f->>'name', p_f->>'who');
  who := lower(btrim(coalesce(p_f->>'who', p_f->>'author', '')));
  host := public._dom(p_url);
  select nullif(lower(primary_domain), '') into firm_dom from firms where id = p_firm;

  if p_section = 'legal' or public._court_register(p_url) then
    if public._court_register(p_url) or base = 1 then
      lvl := 1; outcome := 'published'; reason := null;
    else
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: lawsuit source is not CourtListener, PACER, or uscourts.gov';
    end if;
    return next; return;
  end if;

  if p_section = 'founders' then
    if who in ('', 'anonymous', 'anon', 'unknown')
       and coalesce(p_f->>'quote', '') !~* 'founder|i founded'
       and coalesce(p_f->>'type', '') !~* 'founder' then
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: anonymous, no founder claim';
      return next; return;
    end if;
    if not (public._host_is(p_url, 'reddit.com') or public._host_is(p_url, 'x.com')
            or public._host_is(p_url, 'twitter.com') or public._host_is(p_url, 'linkedin.com')) then
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: review is not from Reddit, X, or LinkedIn';
      return next; return;
    end if;
    if coalesce(btrim(p_f->>'quote'), '') = '' then
      lvl := null; outcome := 'failure'; reason := 'review is not copied word for word';
      return next; return;
    end if;
    if not public._names_firm(p_firm, blob) then
      lvl := null; outcome := 'failure'; reason := 'off-topic: review does not name the firm';
      return next; return;
    end if;
    if who !~* 'founder' and coalesce(p_f->>'quote', '') !~* 'founder|i founded'
       and coalesce(p_f->>'type', '') !~* 'founder' then
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: writer does not say they are a founder';
      return next; return;
    end if;
    lvl := 2; outcome := 'published'; reason := null;
    return next; return;
  end if;

  if p_section in ('press', 'timeline') then
    if public._known_outlet(p_url) then
      if public._names_firm(p_firm, blob) then
        lvl := 2; outcome := 'published'; reason := null;
      else
        lvl := null; outcome := 'failure'; reason := 'off-topic: story does not name the firm';
      end if;
    else
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: unknown outlet, not shown';
    end if;
    return next; return;
  end if;

  if p_section = 'people' then
    if public._host_is(p_url, 'sec.gov') or public._host_is(p_url, 'adviserinfo.sec.gov') then
      lvl := 1; outcome := 'published'; reason := null;
    elsif firm_dom is not null and (host = firm_dom or host like '%.' || firm_dom) then
      lvl := 2; outcome := 'published'; reason := null;
    elsif public._host_is(p_url, 'linkedin.com') and p_url ~* '/in/' then
      lvl := 2; outcome := 'published'; reason := null;
    else
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: people source is not Form ADV, the team page, or that person''s LinkedIn history';
    end if;
    return next; return;
  end if;

  if p_section = 'deals' then
    if public._host_is(p_url, 'sec.gov') then
      lvl := 2; outcome := 'published'; reason := null;
    elsif public._known_outlet(p_url) then
      if public._names_firm(p_firm, blob) then
        lvl := 2; outcome := 'published'; reason := null;
      else
        lvl := null; outcome := 'failure'; reason := 'off-topic: deal story does not name the firm';
      end if;
    else
      company_key := lower(regexp_replace(coalesce(p_f->>'company', ''), '[^a-zA-Z0-9]', '', 'g'));
      if length(company_key) >= 3 and position(company_key in lower(regexp_replace(coalesce(host, ''), '[^a-zA-Z0-9]', '', 'g'))) > 0
         and (firm_dom is null or (host <> firm_dom and host not like '%.' || firm_dom)) then
        lvl := 2; outcome := 'published'; reason := null;
      else
        lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: deal source is not a company press release, Form D, or a known outlet';
      end if;
    end if;
    return next; return;
  end if;

  if p_section = 'social' then
    if firm_dom is not null and (host = firm_dom or host like '%.' || firm_dom) then
      lvl := 2; outcome := 'published'; reason := null;
    else
      lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: social count is not from an account linked on the firm site';
    end if;
    return next; return;
  end if;

  if p_section in ('portfolio', 'sectors') then
    if coalesce(p_f->>'domain', '') <> '' and public._host_is(p_url, p_f->>'domain') then
      lvl := 2; outcome := 'published'; reason := null;
    else
      company_key := lower(regexp_replace(coalesce(p_f->>'company', ''), '[^a-zA-Z0-9]', '', 'g'));
      if length(company_key) >= 3 and position(company_key in lower(regexp_replace(coalesce(host, ''), '[^a-zA-Z0-9]', '', 'g'))) > 0 then
        lvl := 2; outcome := 'published'; reason := null;
      else
        lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: portfolio source is not the company''s own site';
      end if;
    end if;
    return next; return;
  end if;

  if base in (1, 2) then
    lvl := base; outcome := 'published'; reason := null;
  elsif base is null then
    lvl := null; outcome := 'failure'; reason := 'link is not real (missing, not http, or a search/chat page)';
  else
    lvl := 3; outcome := 'unconfirmed'; reason := 'Unconfirmed: elsewhere online, not shown';
  end if;
  return next;
end $$;
revoke all on function public._checker_decide(uuid, text, jsonb, text, int, jsonb) from public, anon, authenticated;
revoke all on function public._names_firm(uuid, text) from public, anon, authenticated;
revoke all on function public._known_outlet(text) from public, anon, authenticated;
revoke all on function public._court_register(text) from public, anon, authenticated;
revoke all on function public._host_is(text, text) from public, anon, authenticated;

create or replace function public.checker_publish_firm(p_firm uuid, p_write boolean default false, p_probes jsonb default null)
returns jsonb
language plpgsql security definer set search_path = bots, public as $$
declare e bots.research_enrichments; it record; lvl smallint; n int; url text; outcome text; reason text;
  pub int := 0; held int := 0; fail int := 0; skip int := 0; unconf int := 0;
  hq text; hq_level smallint; dom text; open_ok boolean;
begin
  if not public._lab_firm(p_firm) then
    return jsonb_build_object('error', 'checker is lab firms only');
  end if;
  select * into e from research_enrichments
   where firm_id = p_firm and valid order by id desc limit 1;
  if e.id is null then
    return jsonb_build_object('firm_id', p_firm, 'enrichment_id', null, 'published', 0, 'held', 0, 'failure', 0, 'skipped', 0, 'unconfirmed', 0);
  end if;
  for it in select * from public.checked_items(e.payload) c where c.outcome = 'ok' order by c.n loop
    url := it.url;
    n := public._checker_check_n(it.section, url);
    select d.lvl, d.outcome, d.reason into lvl, outcome, reason
      from public._checker_decide(p_firm, it.section, it.f, url, n, p_probes) d;
    if outcome = 'published' and public._checker_exists(p_firm, it.section, it.f, url) then
      outcome := 'skipped'; reason := 'already on the page, not re-checked';
    end if;
    if outcome = 'published' and p_write then
      begin
        perform public._checker_write(p_firm, it.section, it.f, url, lvl, n);
      exception when others then
        outcome := 'failure'; reason := 'write failed: ' || sqlerrm;
      end;
    end if;
    if outcome = 'published' then pub := pub + 1;
    elsif outcome = 'unconfirmed' then unconf := unconf + 1; held := held + 1;
    elsif outcome = 'failure' then fail := fail + 1;
    else skip := skip + 1; end if;
    if p_write and outcome in ('failure', 'unconfirmed') then
      insert into checker_holding(firm_id, origin, origin_id, kind, url, outcome, reason, item)
      values (p_firm, 'enrichment', e.id, it.section, url, case when outcome = 'unconfirmed' then 'unconfirmed' else 'failure' end, reason, it.item);
    end if;
  end loop;
  select f.hq, f.primary_domain into hq, dom from firms f where f.id = p_firm;
  select public._source_level(x.url, p_firm, null) into hq_level
    from (
      select coalesce(i->>'source', i->>'url') url
        from jsonb_array_elements(coalesce(e.payload->'sections'->'Overview', '[]'::jsonb)) i
       where lower(coalesce(i->>'label', '')) in ('hq', 'headquarters')
    ) x
   where public._source_level(x.url, p_firm, null) in (1, 2)
   order by public._source_level(x.url, p_firm, null) limit 1;
  return jsonb_build_object(
    'firm_id', p_firm, 'enrichment_id', e.id, 'switch', public._checker_publish_on(),
    'published', pub, 'unconfirmed', unconf, 'held', held, 'failure', fail, 'skipped', skip,
    'submissions_in_holding', (select count(*) from research_submissions s
       where s.registry_id = (select registry_id from firms where id = p_firm)),
    'header', jsonb_build_object('name', (select coalesce(display_name, name) from firms where id = p_firm),
      'short_name', (select short_name from firms where id = p_firm),
      'website', dom, 'hq', hq, 'hq_source_level', hq_level),
    'match', (select jsonb_build_object('firm_id', m.firm_id, 'note', m.note)
                from public.checker_match_firm((select registry_id from firms where id = p_firm), dom,
                     (select name from firms where id = p_firm), hq) m limit 1));
end $$;
revoke all on function public.checker_publish_firm(uuid, boolean, jsonb) from public, anon, authenticated;
