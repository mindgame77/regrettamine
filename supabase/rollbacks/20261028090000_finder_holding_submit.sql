-- Puts the claim check back on research_submit and lets the Enricher publish at ingest again.
-- Does not delete page rows or submission rows. Does not turn checker_publish on.

update bots.ingest_settings set value = 'false' where key = 'checker_publish';

create or replace function public.research_submit(p_id text, p_bot text, p_payload jsonb, p_count int, p_valid boolean, p_errors jsonb)
returns jsonb language plpgsql security definer set search_path = bots, public as $$
declare
  q research_queue;
  s_id bigint;
  v_holder boolean;
  v_prior boolean;
  v_recent int;
begin
  perform bots.apply_limits();
  select count(*) into v_recent from research_submissions
   where bot_id = p_bot and received_at > now() - interval '1 minute';
  if v_recent >= 20 then
    raise exception 'rate_limited: max 20 uploads per minute per bot, retry shortly';
  end if;
  select * into q from research_queue where registry_id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown registry_id'); end if;
  v_holder := q.claimed_by is not distinct from p_bot;
  v_prior := q.prior_claimed_by is not null
    and q.prior_claimed_by = p_bot
    and not v_holder
    and q.status in ('claimed', 'queued')
    and (
      q.lane in ('paid', 'request')
      or exists (
        select 1 from ondemand_jobs j
         where j.registry_id = q.registry_id and j.status in ('queued', 'in_progress'))
    );
  if q.status not in ('claimed', 'queued') or (not v_holder and not v_prior) then
    return jsonb_build_object('ok', false, 'error', 'firm not claimed by this bot_id (status ' || q.status || ')');
  end if;
  insert into research_submissions (registry_id, bot_id, payload, record_count, valid, errors)
    values (p_id, p_bot, p_payload, p_count, p_valid, p_errors)
    returning id into s_id;
  if p_valid then
    if v_holder or q.claimed_by is null then
      update research_queue
         set status = 'submitted', submitted_at = now(), last_error = null, updated_at = now()
       where registry_id = p_id;
    end if;
    return jsonb_build_object('ok', true, 'submission_id', s_id, 'status', 'submitted');
  end if;
  if v_holder or (q.claimed_by is null and not v_prior) then
    update research_queue
       set attempts = attempts + 1, last_error = left(p_errors::text, 2000), updated_at = now(), claimed_at = null,
           status = case when attempts + 1 >= 3 then 'failed' else 'queued' end
     where registry_id = p_id
     returning * into q;
    return jsonb_build_object('ok', false, 'submission_id', s_id, 'status', q.status, 'attempts', q.attempts);
  end if;
  return jsonb_build_object('ok', false, 'submission_id', s_id, 'status', q.status, 'attempts', q.attempts);
end $$;

create or replace function public._enrichment_after_insert() returns trigger
language plpgsql security definer set search_path = bots, public as $$
begin
  if new.valid and new.bot_id = 'toxy-enricher' and new.firm_id is not null then
    perform promote_enrichment(new.firm_id);
  end if;
  if new.valid then
    perform search_log_from_enrichment(new.id);
    perform refresh_feedback_patterns();
  end if;
  return null;
end $$;
