-- Stale bot claims are released after 6 hours instead of 2 (approved by Alex). Logic otherwise unchanged.
CREATE OR REPLACE FUNCTION public.research_claim(p_bot text, p_count integer)
 RETURNS SETOF research_queue
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r research_queue;
begin
  -- auto-release stale claims (>6h); an open paid job goes back to queued with them
  with rel as (
    update research_queue set status='queued', claimed_by=null, claimed_at=null,
      last_error = 'claim expired (' || coalesce(claimed_by,'?') || ')', updated_at=now()
     where status='claimed' and claimed_at < now() - interval '6 hours' returning registry_id), j as (
    update ondemand_jobs set status = 'queued', claimed_at = null, claimed_by = null
     where status = 'in_progress' and registry_id in (select registry_id from rel) returning id)
  update research_requests set status = 'queued' where status = 'in_progress' and job_id in (select id from j);
  if p_bot = 'toxy-researcher-3' then
    for r in
      update research_queue q set status='claimed', claimed_by=p_bot, claimed_at=now(), updated_at=now()
       where q.registry_id = (select registry_id from research_queue
                              where status='queued' and lane='paid' and (retry_after is null or retry_after <= now())
                              order by paid_at, priority, registry_id limit 1 for update skip locked)
      returning q.*
    loop
      with j as (update ondemand_jobs set status = 'in_progress', claimed_at = now(), claimed_by = p_bot
                 where registry_id = r.registry_id and status in ('queued', 'in_progress') returning id)
      update research_requests set status = 'in_progress' where status = 'queued' and job_id in (select id from j);
      return next r;
    end loop;
    return;
  end if;
  return query
  update research_queue q set status='claimed', claimed_by=p_bot, claimed_at=now(), updated_at=now()
   where q.registry_id in (select registry_id from research_queue
                            where status='queued' and lane <> 'paid' and (retry_after is null or retry_after <= now())
                            order by priority limit greatest(1, least(p_count,300)) for update skip locked)
  returning q.*;
end $function$;

CREATE OR REPLACE FUNCTION public.research_claim_gaps(p_bot text, p_registry text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rid text; q research_queue; gs jsonb;
begin
  if coalesce(p_bot,'') = '' then return jsonb_build_object('ok',false,'error','bot_id required'); end if;
  update research_gaps set status='open', claimed_by=null, claimed_at=null, updated_at=now()
   where status='claimed' and claimed_at < now() - interval '6 hours';
  select g.registry_id into rid from research_gaps g join research_queue rq using (registry_id)
   where g.status='open' and (p_registry is null or g.registry_id=p_registry)
     and (rq.status='submitted' or (rq.status='claimed' and rq.claimed_by=p_bot))
   order by g.created_at, g.id limit 1 for update of rq skip locked;
  if rid is null then return jsonb_build_object('ok',true,'gaps','[]'::jsonb,'none_left',true); end if;
  update research_queue set status='claimed', claimed_by=p_bot, claimed_at=now(), updated_at=now(),
         last_error='gap-fill claim' where registry_id=rid returning * into q;
  with u as (update research_gaps set status='claimed', claimed_by=p_bot, claimed_at=now(), updated_at=now()
              where registry_id=rid and status='open' returning id, check_id, reason, tried_routes, detail)
  select jsonb_agg(to_jsonb(u) order by id) into gs from u;
  return jsonb_build_object('ok',true,'registry_id',rid,'name',q.name,'latest_valid_submission',
    (select max(id) from research_submissions where registry_id=rid and valid),'gaps',gs,'none_left',false);
end $function$;

CREATE OR REPLACE FUNCTION public.ingest_progress()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'by_status', research_status(),
    'skipped', (select count(*) from research_queue where status='skipped'),
    'waiting_retry', (select count(*) from research_queue where status='queued' and retry_after > now()),
    'queue_total', (select count(*) from research_queue),
    'submissions_last_hour', (select count(*) from research_submissions where received_at > now() - interval '1 hour'),
    'invalid_last_hour', (select count(*) from research_submissions where received_at > now() - interval '1 hour' and not valid),
    'error_rate_last_hour', (select round(avg(case when valid then 0 else 1 end)::numeric, 3) from research_submissions where received_at > now() - interval '1 hour'),
    'submissions_total', (select count(*) from research_submissions),
    'records_total', (select coalesce(sum(record_count),0) from research_submissions where valid),
    'stale_claims', (select count(*) from research_queue where status='claimed' and claimed_at < now() - interval '6 hours'),
    'paused', (select value from ingest_settings where key='ingest_paused'),
    'db_size_bytes', pg_database_size(current_database()),
    'db_size', pg_size_pretty(pg_database_size(current_database())),
    'submissions_size', pg_size_pretty(pg_total_relation_size('public.research_submissions'))) $function$
;

CREATE OR REPLACE FUNCTION public.research_gaps_list(p_registry text, p_limit integer)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(to_jsonb(g) - 'source_submission' order by g.registry_id, g.id), '[]'::jsonb) from (
    select id, registry_id, check_id, reason, tried_routes, detail, status, claimed_by, created_at, source_submission
      from research_gaps
     where (status='open' or (status='claimed' and claimed_at < now() - interval '6 hours'))
       and (p_registry is null or registry_id = p_registry)
     order by registry_id, id limit greatest(1, least(coalesce(p_limit,100),500))) g $function$
;
