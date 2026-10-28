-- A finder can submit an item for any firm without claiming it.
-- The row lands in bots.research_submissions and stays there. The queue claim is not touched.
-- Page triggers that used to run on a valid upload do not run for this insert.
-- checker_publish stays false. While it is false, toxy-enricher still publishes at ingest.
-- While it is true, a lab firm's enrich row is copied into holding and is not written to a page table.
-- Rollback: supabase/rollbacks/20261028090000_finder_holding_submit.sql

insert into bots.ingest_settings(key, value)
values ('checker_publish', 'false')
on conflict (key) do nothing;

create or replace function public._checker_publish_on() returns boolean
language sql stable security definer set search_path = bots, public as $$
  select coalesce((select value from ingest_settings where key = 'checker_publish'), 'false') = 'true';
$$;
revoke all on function public._checker_publish_on() from public, anon, authenticated;

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
  if q.status in ('claimed', 'queued') and (v_holder or v_prior) then
    perform set_config('app.finder_holding', '', true);
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
  end if;
  -- Not the claim holder. Store the item for the Checker. Do not take the claim and do not write a page.
  -- Clear the flag after the insert so a later claimed submit in this transaction still closes its job.
  perform set_config('app.finder_holding', '1', true);
  begin
    insert into research_submissions (registry_id, bot_id, payload, record_count, valid, errors)
      values (p_id, p_bot, p_payload, p_count, p_valid, p_errors)
      returning id into s_id;
  exception when others then
    perform set_config('app.finder_holding', '', true);
    raise;
  end;
  perform set_config('app.finder_holding', '', true);
  return jsonb_build_object('ok', coalesce(p_valid, false), 'submission_id', s_id, 'status', 'holding', 'held_for_checker', true);
end $$;

create or replace function public.ondemand_done_trg() returns trigger
language plpgsql security definer set search_path = bots, public as $$
declare t text;
begin
  if current_setting('app.finder_holding', true) = '1' then return null; end if;
  if not new.valid then return null; end if;
  begin
    t := coalesce(_registry_target(new.registry_id), new.registry_id);
    with j as (update ondemand_jobs set status = 'done', done_at = now(), submission_id = new.id,
                 missing_checks = _ondemand_missing(firm_id)
               where registry_id in (t, new.registry_id) and status in ('queued', 'in_progress') returning id)
    update research_requests set status = 'done', done_at = now() where job_id in (select id from j) and status in ('queued', 'in_progress');
    update research_queue set lane = 'normal', paid_at = null where registry_id in (t, new.registry_id) and lane = 'paid';
  exception when others then
    raise warning 'ondemand_done: submission % registry %: %', new.id, new.registry_id, sqlerrm;
  end;
  return null;
end $$;

create or replace function public.firm_request_done_trg() returns trigger
language plpgsql security definer set search_path = bots, public as $$
declare q research_queue; v_req bigint;
begin
  if current_setting('app.finder_holding', true) = '1' then return null; end if;
  if not new.valid or new.registry_id !~ '^req-[0-9]+$' then return null; end if;
  begin
    select * into q from research_queue where registry_id = new.registry_id;
    if q.lane is distinct from 'request' or q.list_source = 'check_request' then return null; end if;
    v_req := substring(new.registry_id from 5)::bigint;
    if (select status from firm_requests where firm_requests.id = v_req) = 'open' then perform firm_request_link(v_req, new.registry_id); end if;
    update research_queue set lane = 'normal', paid_at = null, updated_at = now() where registry_id = new.registry_id and lane = 'request';
  exception when others then
    raise warning 'firm_request_done: submission % registry %: %', new.id, new.registry_id, sqlerrm;
  end;
  return null;
end $$;

create or replace function public.check_request_done_trg() returns trigger
language plpgsql security definer set search_path = bots, public as $$
declare q research_queue; v_id bigint; fid uuid;
begin
  if current_setting('app.finder_holding', true) = '1' then return null; end if;
  if not new.valid then return null; end if;
  begin
    select * into q from research_queue where registry_id = new.registry_id;
    if q.list_source is distinct from 'check_request' then return null; end if;
    v_id := substring(q.registry_id from '([0-9]+)$')::bigint;
    select id into fid from firms
     where registry_id = coalesce(_registry_target(new.registry_id), new.registry_id) and deleted_at is null
     order by created_at limit 1;
    if fid is not null then update check_requests set firm_id = fid where id = v_id and firm_id is null; end if;
    perform _check_request_file(v_id);
  exception when others then
    raise warning 'check_request_done: submission % registry %: %', new.id, new.registry_id, sqlerrm;
  end;
  return null;
end $$;

create or replace function public.research_gaps_sync() returns trigger
language plpgsql security definer set search_path = bots, public as $$
declare c jsonb; st text; ci text; rs text; tr text;
begin
  if current_setting('app.finder_holding', true) = '1' then return new; end if;
  if not new.valid or jsonb_typeof(new.payload->'coverage') is distinct from 'array' then return new; end if;
  for c in select * from jsonb_array_elements(new.payload->'coverage') loop
    ci := left(nullif(trim(c->>'checklist_item'),''),200); st := c->>'status';
    continue when ci is null;
    if st in ('records','none_found') then
      update research_gaps set status='resolved', resolved_at=now(), resolved_by_submission=new.id, updated_at=now(),
             claimed_by=null, claimed_at=null
       where registry_id=new.registry_id and check_id=ci and status<>'resolved';
    elsif st in ('blocked','not_searched') then
      rs := coalesce(nullif(c->>'gap_reason',''), case st when 'blocked' then 'blocked' else 'not_searched' end);
      if rs not in ('blocked','paywall','login_required','not_found_source','not_searched','time_cap','out_of_scope') then rs := st; end if;
      tr := case jsonb_typeof(c->'tried_routes') when 'array' then (select string_agg(x,'; ') from jsonb_array_elements_text(c->'tried_routes') x)
                 else c->>'tried_routes' end;
      insert into research_gaps (registry_id, check_id, reason, tried_routes, detail, source_submission)
        values (new.registry_id, ci, rs, left(tr,4000), left(c->>'note',4000), new.id)
      on conflict (registry_id, check_id) where status <> 'resolved' do update
        set reason=excluded.reason, tried_routes=excluded.tried_routes, detail=excluded.detail,
            source_submission=excluded.source_submission, status='open', claimed_by=null, claimed_at=null, updated_at=now();
    end if;
  end loop;
  return new;
end $$;

-- Switch off: Enricher still publishes. Switch on and a lab firm: holding only, no page write.
create or replace function public._enrichment_after_insert() returns trigger
language plpgsql security definer set search_path = bots, public as $$
declare hold boolean := false;
begin
  if new.valid and new.bot_id = 'toxy-enricher' and new.firm_id is not null then
    if to_regprocedure('public._checker_publish_on()') is not null then
      execute 'select public._checker_publish_on() and public._lab_firm($1)' into hold using new.firm_id;
    end if;
    if hold then
      perform set_config('app.finder_holding', '1', true);
      begin
        insert into research_submissions(bot_id, registry_id, payload, record_count, valid, errors)
        values (new.bot_id, new.registry_id, new.payload, new.accepted, coalesce(new.valid, false), new.errors);
      exception when others then
        if to_regclass('bots.checker_holding') is not null then
          execute 'insert into bots.checker_holding(firm_id, origin, origin_id, kind, outcome, reason, item) values ($1,$2,$3,$4,$5,$6,$7)'
            using new.firm_id, 'enrichment', new.id, 'row', 'failure', sqlerrm, new.payload;
        end if;
      end;
      perform set_config('app.finder_holding', '', true);
    else
      perform promote_enrichment(new.firm_id);
    end if;
  end if;
  if new.valid then
    perform search_log_from_enrichment(new.id);
    perform refresh_feedback_patterns();
  end if;
  return null;
end $$;
revoke all on function public._enrichment_after_insert() from public, anon, authenticated;
