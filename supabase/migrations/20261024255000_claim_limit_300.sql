-- research_claim: claim up to 300 firms per call (was 5). Paid lane (toxy-researcher-3, one paid firm per call),
-- skip-locked claiming and the 2-hour release of unfinished claims are unchanged.
CREATE OR REPLACE FUNCTION public.research_claim(p_bot text, p_count integer)
 RETURNS SETOF research_queue
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r research_queue;
begin
  -- auto-release stale claims (>2h); an open paid job goes back to queued with them
  with rel as (
    update research_queue set status='queued', claimed_by=null, claimed_at=null,
      last_error = 'claim expired (' || coalesce(claimed_by,'?') || ')', updated_at=now()
     where status='claimed' and claimed_at < now() - interval '2 hours' returning registry_id), j as (
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
