-- Research queue loop fix (approved by Alex 2026-10-23).
-- fail => back of the queue (priority behind all queued) + retry_after = now()+30min; claim skips future retry_after.
-- skip => status 'skipped' immediately, no retries (out of scope / duplicate). Atomic claim, 2h stale release, 3-try limit kept.
alter table public.research_queue add column if not exists retry_after timestamptz;
alter table public.research_queue drop constraint if exists research_queue_status_check;
alter table public.research_queue add constraint research_queue_status_check
  check (status in ('queued','claimed','submitted','failed','skipped','accepted','rejected'));

create or replace function public.research_claim(p_bot text, p_count int) returns setof public.research_queue
language plpgsql security definer set search_path = public as $$
begin
  -- auto-release stale claims (>2h)
  update research_queue set status='queued', claimed_by=null, claimed_at=null,
    last_error = 'claim expired (' || coalesce(claimed_by,'?') || ')', updated_at=now()
   where status='claimed' and claimed_at < now() - interval '2 hours';
  return query
  update research_queue q set status='claimed', claimed_by=p_bot, claimed_at=now(), updated_at=now()
   where q.registry_id in (select registry_id from research_queue
                            where status='queued' and (retry_after is null or retry_after <= now())
                            order by priority limit greatest(1, least(p_count,5)) for update skip locked)
  returning q.*;
end $$;

create or replace function public.research_skip(p_id text, p_bot text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare q research_queue;
begin
  update research_queue set status='skipped', last_error=left(coalesce(nullif(p_reason,''),'skip: (no reason)'),2000),
    claimed_by=null, claimed_at=null, retry_after=null, updated_at=now()
   where registry_id=p_id and status='claimed' and claimed_by = p_bot returning * into q;
  if not found then return jsonb_build_object('ok',false,'error','firm not claimed by this bot_id'); end if;
  return jsonb_build_object('ok',true,'status',q.status,'attempts',q.attempts);
end $$;

create or replace function public.research_fail(p_id text, p_bot text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare q research_queue; back int;
begin
  if lower(ltrim(coalesce(p_reason,''))) like 'skip:%' then
    return research_skip(p_id, p_bot, p_reason); end if;
  select coalesce(max(priority),0) + 1 into back from research_queue where status in ('queued','claimed');
  update research_queue set attempts=attempts+1, last_error=left(coalesce(p_reason,'(no reason)'),2000),
    status = case when attempts+1 >= 3 then 'failed' else 'queued' end,
    priority = case when attempts+1 >= 3 then priority else greatest(priority, back) end,
    retry_after = case when attempts+1 >= 3 then null else now() + interval '30 minutes' end,
    claimed_by=null, claimed_at=null, updated_at=now()
   where registry_id=p_id and status='claimed' and claimed_by = p_bot returning * into q;
  if not found then return jsonb_build_object('ok',false,'error','firm not claimed by this bot_id'); end if;
  return jsonb_build_object('ok',true,'status',q.status,'attempts',q.attempts,'retry_after',q.retry_after);
end $$;

create or replace function public.research_status() returns jsonb language sql security definer set search_path = public as $$
  select '{"queued":0,"claimed":0,"submitted":0,"failed":0,"skipped":0}'::jsonb
    || coalesce(jsonb_object_agg(status, n),'{}'::jsonb) from (select status, count(*) n from research_queue group by 1) s $$;

create or replace function public.ingest_progress() returns jsonb language sql security definer set search_path = public as $$
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
    'stale_claims', (select count(*) from research_queue where status='claimed' and claimed_at < now() - interval '2 hours'),
    'paused', (select value from ingest_settings where key='ingest_paused'),
    'db_size_bytes', pg_database_size(current_database()),
    'db_size', pg_size_pretty(pg_database_size(current_database())),
    'submissions_size', pg_size_pretty(pg_total_relation_size('public.research_submissions'))) $$;

do $$ declare f text; begin
  foreach f in array array['research_claim(text,int)','research_fail(text,text,text)','research_skip(text,text,text)',
    'research_status()','ingest_progress()'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop; end $$;
