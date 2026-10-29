-- Rollback of 20261029230000_social_count_history.sql. Restores _checker_social and checker_publish_submission.
-- Facts superseded by fix 3 are NOT auto-restored: to undo a replacement, set the old row (social_count_history.fact_id)
-- back to status 'current', strip ':superseded:<id>' from its external_id, and mark the replacing row 'superseded'.

create or replace function public._checker_social(p_firm uuid, p_f jsonb, p_url text)
returns table(lvl smallint, outcome text, reason text)
language plpgsql security definer set search_path to 'bots', 'public' as $$
declare acct text := public._checker_social_platform(p_f->>'platform'); u text := p_f->>'url';
begin
  if coalesce(p_f->>'linked_from_firm_site', '') <> 'true' then
    return query select null::smallint, 'skipped'::text, 'skipped, published via _firm_social'::text; return;
  end if;
  if acct is null or acct not in ('linkedin', 'x', 'youtube', 'instagram', 'tiktok', 'substack') then
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

revoke all on function public._checker_social(uuid, jsonb, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.checker_publish_submission(p_id bigint, p_probes jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bots', 'public'
AS $function$
declare sub bots.research_submissions; fid uuid; it record; lvl smallint; ncheck int; outcome text; reason text;
  pub int := 0; skip int := 0; fail int := 0; unconf int := 0; merged int := 0; noted int := 0; internal int := 0;
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
    -- our own write / DB-constraint errors are not the bot's fault: counted apart, never as a failure
    if outcome = 'failure' and public._checker_internal_error(reason) then outcome := 'internal'; end if;
    if outcome = 'published' then pub := pub + 1;
    elsif outcome = 'merged' then merged := merged + 1;
    elsif outcome = 'note' then noted := noted + 1;
    elsif outcome = 'skipped' then skip := skip + 1;
    elsif outcome = 'unconfirmed' then unconf := unconf + 1;
    elsif outcome = 'internal' then internal := internal + 1;
    else fail := fail + 1; end if;
    if outcome is distinct from 'published' and outcome is distinct from 'merged' then
      reasons := reasons || jsonb_build_array(jsonb_build_object('section', it.section, 'url', coalesce(it.f->>'url', it.url),
        'outcome', coalesce(outcome, 'failure'), 'reason', coalesce(reason, 'no reason given')));
    end if;
    if outcome in ('failure', 'unconfirmed', 'internal') then
      insert into checker_holding(firm_id, origin, origin_id, kind, url, outcome, reason, item)
      values (fid, 'submission', sub.id, it.section, it.url,
              case when outcome = 'unconfirmed' then 'unconfirmed' else 'failure' end, reason, it.f);
    end if;
  end loop;
  return jsonb_build_object('ran', true, 'firm_id', fid, 'published', pub, 'merged', merged, 'note', noted,
    'skipped', skip, 'unconfirmed', unconf, 'failure', fail, 'internal', internal, 'reasons', reasons);
end $function$;

drop table if exists public.social_count_history;

delete from public.firm_page_cache;
