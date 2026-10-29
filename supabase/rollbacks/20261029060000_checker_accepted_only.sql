-- Rollback for 20261029060000_checker_accepted_only: restores the live definitions from before Step B.

drop function if exists public._checker_entry_gate(bigint, jsonb);

-- Layer 1 version of _entry_check_reasons (from 20261029050000_entry_check_layer1.sql).
create or replace function public._entry_check_reasons(p jsonb, p_firm_dom text)
 returns text[] language plpgsql stable set search_path = public, extensions as $$
declare
  r text[] := '{}';
  it record; recs jsonb; rec jsonb; lvl int; sec text;
  dom text := nullif(regexp_replace(lower(coalesce(p_firm_dom, '')), '^www\.', ''), '');
begin
  if p is null or jsonb_typeof(p) <> 'object' then return array['empty or unreadable upload']; end if;
  recs := case when jsonb_typeof(p->'records') = 'array' then p->'records' else '[]'::jsonb end;

  if not exists (select 1 from public._checker_payload_items(p)) then
    r := r || 'no items in the upload'::text;
  end if;

  for it in select * from public._checker_payload_items(p) loop
    rec := case when it.n >= 1 and jsonb_typeof(p->'records') = 'array' then recs->(it.n - 1) else null end;
    sec := public._entry_section(it.section, rec->>'field_path');
    -- 1) link present and well-formed http(s)
    if it.url is null or btrim(it.url) = '' then
      r := r || 'no source link'::text;
    elsif btrim(it.url) !~* '^https?://[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+(:\d+)?([/?#][^\s]*)?$' then
      r := r || 'source link is not a valid http(s) URL'::text;
    elsif public._src_search_page(it.url) then
      r := r || 'source link is a search or chat page'::text;
    end if;
    -- 2) source level 1 to 3
    lvl := case when it.n = 0 then 2 else public._entry_level(rec, it.f) end;  -- n = 0: the firm's own website item
    if lvl is null then r := r || 'no source level'::text;
    elsif lvl not between 1 and 3 then r := r || ('source level ' || lvl || ' is not 1 to 3')::text;
    end if;
    -- 4) dates: never rejected; normalized or cleared by _entry_fix_payload.
    -- 5) status words
    if it.section = 'legal' and public._entry_status_bad(it.f) is not null then r := r || public._entry_status_bad(it.f); end if;
    -- 6b) thesis over 1,000 characters (A9.19): never rejected; cut by _entry_fix_payload.
    -- 7) no news from the firm's own site
    if sec in ('press', 'news', 'timeline') and dom is not null and it.url is not null
       and (public._dom(it.url) = dom or public._dom(it.url) like '%.' || dom) then
      r := r || 'news item from the firm''s own website or blog'::text;
    end if;
  end loop;

  -- 6) A9 list limits: never rejected; extra items archived by _entry_fix_payload.

  return (select coalesce(array_agg(x order by o), '{}') from (select x, min(o) o from unnest(r) with ordinality u(x, o) group by x) s);
end $$;

CREATE OR REPLACE FUNCTION public.checker_publish_submission(p_id bigint, p_probes jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bots', 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.checker_drain(p_limit integer DEFAULT 10)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bots', 'public'
AS $function$
declare r record; report jsonb; n int := 0; lim int := greatest(1, least(coalesce(p_limit, 10), 50));
begin
  update research_submissions set door_status = 'ready'
   where door_status = 'waiting' and ready_at <= now();
  for r in
    select s.id, s.bot_id from research_submissions s
     where s.door_status = 'ready' and s.checked_at is null
       and exists (
         select 1 from firms f
          where f.deleted_at is null and public._lab_firm(f.id)
            and f.registry_id = coalesce(public._registry_target(s.registry_id), s.registry_id))
     order by s.received_at, s.id
     limit lim
     for update skip locked
  loop
    report := public.checker_publish_submission(r.id);
    update research_submissions set checked_at = now(), door_status = 'checked', checker_report = report where id = r.id;
    perform public._door_fail_rate(r.bot_id);
    n := n + 1;
  end loop;
  return n;
end $function$;

CREATE OR REPLACE FUNCTION public.checker_on_submission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bots', 'public'
AS $function$
declare report jsonb;
begin
  if not public._checker_publish_on() then return null; end if;
  begin
    if new.door_status is null then
      report := public.checker_publish_submission(new.id);
      update research_submissions set checked_at = now(), checker_report = report where id = new.id;
      perform public._door_fail_rate(new.bot_id);
    elsif new.door_status = 'ready' then
      perform public.checker_drain(10);
    end if;
  exception when others then
    insert into checker_holding(firm_id, origin, origin_id, kind, outcome, reason, item)
    values (null, 'submission', new.id, 'row', 'failure', sqlerrm, new.payload);
  end;
  return null;
end $function$;

revoke all on function public.checker_publish_submission(bigint, jsonb) from public, anon, authenticated;
revoke all on function public.checker_drain(integer) from public, anon, authenticated;
revoke all on function public.checker_on_submission() from public, anon, authenticated;
