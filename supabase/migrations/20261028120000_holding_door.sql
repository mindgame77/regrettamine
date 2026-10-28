-- Holding door. Known bots only, each key turns off on its own.
-- 100 distinct firms an hour are checked now. 101 to 300 wait until the next hour.
-- More than 300 distinct firms in an hour blocks that bot's key, freezes what is waiting,
-- and writes one alert. Only door_unblock turns it back on.
-- Exact copies are not stored. The Checker takes ready rows oldest first.
-- A bot whose checked items fail more than half the time, once it has at least 10,
-- is paused and gets one alert. Failed rows still last 7 days. Processed search logs still last 30 days.
-- Rollback: supabase/rollbacks/20261028120000_holding_door.sql

alter table bots.ingest_keys add column if not exists bot_id text;
update bots.ingest_keys set bot_id = name where bot_id is null and name = 'toxy-enricher';
update bots.ingest_keys set bot_id = 'portal-night-bot' where name = 'night-run-1' and bot_id is null;

alter table bots.research_submissions
  add column if not exists door_status text,
  add column if not exists ready_at timestamptz,
  add column if not exists door_key text,
  add column if not exists checked_at timestamptz,
  add column if not exists checker_report jsonb;
create index if not exists research_submissions_door_idx
  on bots.research_submissions (door_status, received_at, id);
create index if not exists research_submissions_door_key_idx
  on bots.research_submissions (door_key) where door_key is not null;

create table if not exists bots.door_alerts (
  id bigserial primary key,
  bot_id text not null,
  kind text not null check (kind in ('attack', 'fail_rate')),
  message text not null,
  created_at timestamptz not null default now(),
  unique (bot_id, kind)
);
alter table bots.door_alerts enable row level security;
revoke all on bots.door_alerts from public, anon, authenticated;

insert into bots.ingest_settings(key, value) values
  ('door_hour_cap', '100'),
  ('door_attack_at', '300'),
  ('door_fail_min', '10')
on conflict (key) do nothing;

create or replace function public._door_key(p_id text, p_payload jsonb) returns text
language sql immutable as $$
  select md5(coalesce(p_id, '') || '|' ||
    coalesce((p_payload #- '{firm,generated_at}' #- '{search_log}')::text, ''));
$$;

create or replace function public._door_known(p_bot text) returns text
language plpgsql stable security definer set search_path = bots, public as $$
declare n int;
begin
  select count(*) into n from ingest_keys;
  if n = 0 then return 'open'; end if;
  if exists (select 1 from ingest_keys k where k.active and (k.name = p_bot or k.bot_id = p_bot)) then
    return 'active';
  end if;
  if exists (select 1 from ingest_keys k where not k.active and (k.name = p_bot or k.bot_id = p_bot)) then
    return 'off';
  end if;
  return 'unknown';
end $$;

create or replace function public._door_alert(p_bot text, p_kind text, p_message text) returns void
language plpgsql security definer set search_path = bots, public as $$
begin
  insert into door_alerts(bot_id, kind, message) values (p_bot, p_kind, p_message)
  on conflict (bot_id, kind) do nothing;
end $$;

create or replace function public._door_admit(p_bot text, p_id text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = bots, public as $$
declare known text; cap int; attack int; dkey text; n int; already boolean;
begin
  perform pg_advisory_xact_lock(hashtext('door:' || coalesce(p_bot, '')));
  known := public._door_known(p_bot);
  if known = 'unknown' then
    return jsonb_build_object('ok', false, 'error', 'unknown bot', 'status', 'rejected');
  end if;
  if known = 'off' then
    return jsonb_build_object('ok', false, 'error', 'bot is off', 'status', 'off');
  end if;
  dkey := public._door_key(p_id, p_payload);
  if exists (select 1 from research_submissions s where s.door_key = dkey) then
    return jsonb_build_object('ok', true, 'status', 'duplicate', 'dropped', true, 'door_key', dkey);
  end if;
  cap := coalesce((select value::int from ingest_settings where key = 'door_hour_cap'), 100);
  attack := coalesce((select value::int from ingest_settings where key = 'door_attack_at'), 300);
  select count(distinct s.registry_id) into n from research_submissions s
   where s.bot_id = p_bot and s.received_at > now() - interval '1 hour'
     and coalesce(s.door_status, 'ready') in ('ready', 'waiting', 'frozen', 'checked');
  already := exists (select 1 from research_submissions s
   where s.bot_id = p_bot and s.registry_id = p_id and s.received_at > now() - interval '1 hour'
     and coalesce(s.door_status, 'ready') in ('ready', 'waiting', 'frozen', 'checked'));
  if not already then n := n + 1; end if;
  if not already and n > attack then
    update ingest_keys set active = false where name = p_bot or bot_id = p_bot;
    update research_submissions set door_status = 'frozen'
     where bot_id = p_bot and door_status = 'waiting';
    perform public._door_alert(p_bot, 'attack',
      'More than ' || attack || ' distinct firms in an hour. Key blocked. Waiting items frozen. Only Alex can unblock.');
    return jsonb_build_object('ok', false, 'error', 'blocked', 'status', 'blocked');
  end if;
  if already or n <= cap then
    return jsonb_build_object('ok', true, 'status', 'ready', 'ready_at', now(), 'door_key', dkey, 'door_status', 'ready');
  end if;
  return jsonb_build_object('ok', true, 'status', 'waiting',
    'ready_at', date_trunc('hour', now()) + interval '1 hour', 'door_key', dkey, 'door_status', 'waiting');
end $$;

create or replace function public._door_fail_rate(p_bot text) returns void
language plpgsql security definer set search_path = bots, public as $$
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
end $$;

create or replace function public.checker_drain(p_limit int default 10) returns int
language plpgsql security definer set search_path = bots, public as $$
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
end $$;
revoke all on function public.checker_drain(int) from public, anon, authenticated;
revoke all on function public._door_key(text, jsonb) from public, anon, authenticated;
revoke all on function public._door_known(text) from public, anon, authenticated;
revoke all on function public._door_alert(text, text, text) from public, anon, authenticated;
revoke all on function public._door_admit(text, text, jsonb) from public, anon, authenticated;
revoke all on function public._door_fail_rate(text) from public, anon, authenticated;

create or replace function public.checker_on_submission() returns trigger
language plpgsql security definer set search_path = bots, public as $$
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
end $$;

create or replace function public.door_unblock(p_bot text) returns jsonb
language plpgsql security definer set search_path = bots, public as $$
declare n int;
begin
  update ingest_keys set active = true where name = p_bot or bot_id = p_bot;
  get diagnostics n = row_count;
  update research_submissions set door_status = 'waiting', ready_at = now()
   where bot_id = p_bot and door_status = 'frozen';
  delete from door_alerts where bot_id = p_bot;
  return jsonb_build_object('ok', true, 'bot_id', p_bot, 'keys', n);
end $$;
revoke all on function public.door_unblock(text) from public, anon, authenticated;

create or replace function public.research_submit(p_id text, p_bot text, p_payload jsonb, p_count int, p_valid boolean, p_errors jsonb)
returns jsonb language plpgsql security definer set search_path = bots, public as $$
declare
  q research_queue; s_id bigint; v_holder boolean; v_prior boolean; v_recent int; door jsonb;
begin
  perform bots.apply_limits();
  select count(*) into v_recent from research_submissions
   where bot_id = p_bot and received_at > now() - interval '1 minute';
  if v_recent >= 20 then
    raise exception 'rate_limited: max 20 uploads per minute per bot, retry shortly';
  end if;
  select * into q from research_queue where registry_id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown registry_id'); end if;
  door := public._door_admit(p_bot, p_id, p_payload);
  if coalesce(door->>'ok', 'false') <> 'true' then return door; end if;
  if door->>'status' = 'duplicate' then return door; end if;
  v_holder := q.claimed_by is not distinct from p_bot;
  v_prior := q.prior_claimed_by is not null
    and q.prior_claimed_by = p_bot and not v_holder and q.status in ('claimed', 'queued')
    and (q.lane in ('paid', 'request') or exists (
      select 1 from ondemand_jobs j where j.registry_id = q.registry_id and j.status in ('queued', 'in_progress')));
  if q.status in ('claimed', 'queued') and (v_holder or v_prior) then
    perform set_config('app.finder_holding', '', true);
    insert into research_submissions (registry_id, bot_id, payload, record_count, valid, errors, door_status, ready_at, door_key)
      values (p_id, p_bot, p_payload, p_count, p_valid, p_errors, door->>'door_status', (door->>'ready_at')::timestamptz, door->>'door_key')
      returning id into s_id;
    if p_valid then
      if v_holder or q.claimed_by is null then
        update research_queue set status = 'submitted', submitted_at = now(), last_error = null, updated_at = now() where registry_id = p_id;
      end if;
      return door || jsonb_build_object('ok', true, 'submission_id', s_id, 'status', case when door->>'status' = 'waiting' then 'waiting' else 'submitted' end);
    end if;
    if v_holder or (q.claimed_by is null and not v_prior) then
      update research_queue
         set attempts = attempts + 1, last_error = left(p_errors::text, 2000), updated_at = now(), claimed_at = null,
             status = case when attempts + 1 >= 3 then 'failed' else 'queued' end
       where registry_id = p_id returning * into q;
      return jsonb_build_object('ok', false, 'submission_id', s_id, 'status', q.status, 'attempts', q.attempts);
    end if;
    return jsonb_build_object('ok', false, 'submission_id', s_id, 'status', q.status, 'attempts', q.attempts);
  end if;
  perform set_config('app.finder_holding', '1', true);
  begin
    insert into research_submissions (registry_id, bot_id, payload, record_count, valid, errors, door_status, ready_at, door_key)
      values (p_id, p_bot, p_payload, p_count, p_valid, p_errors, door->>'door_status', (door->>'ready_at')::timestamptz, door->>'door_key')
      returning id into s_id;
  exception when others then
    perform set_config('app.finder_holding', '', true);
    raise;
  end;
  perform set_config('app.finder_holding', '', true);
  return door || jsonb_build_object('ok', coalesce(p_valid, false), 'submission_id', s_id,
    'status', case when door->>'status' = 'waiting' then 'waiting' else 'holding' end, 'held_for_checker', true);
end $$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'checker-door-drain') then
      perform cron.unschedule('checker-door-drain');
    end if;
    perform cron.schedule('checker-door-drain', '2-59/5 * * * *', 'select public.checker_drain(20)');
  end if;
end $$;
