-- The Checker was firing on insert and then finding nothing, because a domain sent in
-- firm / coverage (with records: []) is not a section item and not a record.
-- A lab firm's website is level 2 when the source is that firm's own site, the link opens,
-- and the host matches the domain. That sets firms.primary_domain.
-- Rollback: supabase/rollbacks/20261028110000_checker_firm_website.sql

do $$ begin
  create extension if not exists http with schema extensions;
exception when others then
  null;
end $$;

create or replace function public._checker_host(p text) returns text
language sql immutable as $$
  select nullif(regexp_replace(coalesce(
    public._dom(case when coalesce(p, '') ~ '://' then p else 'https://' || btrim(p) end),
    lower(btrim(coalesce(p, '')))), '^www\.', ''), '');
$$;

create or replace function public._checker_link_opens(p_url text, p_probes jsonb) returns boolean
language plpgsql as $$
declare st int;
begin
  if p_probes is not null and p_probes ? p_url then
    return coalesce(p_probes->>p_url, '') in ('true', 't', '1');
  end if;
  if to_regprocedure('extensions.http_get(character varying)') is not null then
    begin
      execute 'select status from extensions.http_get($1)' into st using p_url;
      return st between 200 and 399;
    exception when others then
      return false;
    end;
  end if;
  return null;
end $$;

create or replace function public._checker_payload_items(p jsonb)
returns table(n int, section text, f jsonb, url text)
language plpgsql stable as $$
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
end $$;

drop function if exists public.checker_publish_submission(bigint);
create or replace function public.checker_publish_submission(p_id bigint, p_probes jsonb default null) returns jsonb
language plpgsql security definer set search_path = bots, public as $$
declare sub bots.research_submissions; fid uuid; it record; lvl smallint; ncheck int; outcome text; reason text;
  pub int := 0; skip int := 0; fail int := 0; unconf int := 0; merged int := 0; noted int := 0;
  probes jsonb; host text; claimed text; opened boolean; website boolean;
begin
  select * into sub from research_submissions where id = p_id;
  if sub.id is null or not public._checker_publish_on() then
    return jsonb_build_object('ran', false);
  end if;
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
      else
        ncheck := public._checker_check_n(it.section, it.url);
        select d.lvl, d.outcome, d.reason into lvl, outcome, reason
          from public._checker_decide(fid, it.section, it.f, it.url, ncheck, probes) d;
      end if;
      if outcome = 'published' then
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
    if outcome in ('failure', 'unconfirmed') then
      insert into checker_holding(firm_id, origin, origin_id, kind, url, outcome, reason, item)
      values (fid, 'submission', sub.id, it.section, it.url,
              case when outcome = 'unconfirmed' then 'unconfirmed' else 'failure' end, reason, it.f);
    end if;
  end loop;
  return jsonb_build_object('ran', true, 'firm_id', fid, 'published', pub, 'merged', merged, 'note', noted,
    'skipped', skip, 'unconfirmed', unconf, 'failure', fail);
end $$;
revoke all on function public.checker_publish_submission(bigint, jsonb) from public, anon, authenticated;
