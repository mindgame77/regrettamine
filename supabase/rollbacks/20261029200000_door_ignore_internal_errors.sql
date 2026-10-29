-- Rollback for 20261029200000_door_ignore_internal_errors.sql: restores checker_publish_submission (as of #267) and _door_fail_rate.
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

CREATE OR REPLACE FUNCTION public._door_fail_rate(p_bot text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bots', 'public'
AS $function$
declare fails int; total int; need int;
begin
  need := coalesce((select value::int from ingest_settings where key = 'door_fail_min'), 10);
  select coalesce(sum((checker_report->>'failure')::int), 0),
         coalesce(sum(
           coalesce((checker_report->>'failure')::int, 0) + coalesce((checker_report->>'published')::int, 0)
           + coalesce((checker_report->>'merged')::int, 0) + coalesce((checker_report->>'skipped')::int, 0)
           + coalesce((checker_report->>'unconfirmed')::int, 0) + coalesce((checker_report->>'note')::int, 0)
         ), 0)
    into fails, total
    from research_submissions
   where bot_id = p_bot and checked_at > now() - interval '24 hours' and checker_report is not null;
  if total >= need and fails::numeric / total > 0.5 then
    update ingest_keys set active = false where name = p_bot or bot_id = p_bot;
    perform public._door_alert(p_bot, 'fail_rate',
      'More than half of the checked items failed in the last day (' || fails || ' of ' || total || '). Bot paused. Only Alex can unblock.');
  end if;
end $function$;

drop function if exists public._checker_internal_error(text);
