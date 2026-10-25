-- A paid or request job takes the firm immediately. A normal-lane claim (including a
-- gap-fill claim) must not keep the row out of research_claim for toxy-researcher-3.
-- The previous claimant can still submit later: prior_claimed_by is remembered, and
-- research_submit stores that dump as sent. Claims with no paid or request job still
-- expire only after 6 hours.

alter table public.research_queue add column if not exists prior_claimed_by text;

-- Release every normal-lane hold that a paid or request job now owns.
-- Researcher 3's own claim is left alone. prior_claimed_by keeps the bot that was
-- holding the firm so a later upload from that bot is not rejected.
create or replace function public._preempt_normal_claims()
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.research_queue q
     set prior_claimed_by = q.claimed_by,
         lane = case when q.lane = 'request' then 'request' else 'paid' end,
         paid_at = coalesce(q.paid_at, now()),
         status = 'queued',
         claimed_by = null,
         claimed_at = null,
         last_error = left('released for ' || case when q.lane = 'request' then 'request' else 'paid' end
                           || ' lane (' || q.claimed_by || ')', 2000),
         updated_at = now()
   where q.status = 'claimed'
     and q.claimed_by is not null
     and q.claimed_by is distinct from 'toxy-researcher-3'
     and (
       q.lane in ('paid', 'request')
       or exists (
         select 1 from public.ondemand_jobs j
          where j.registry_id = q.registry_id and j.status in ('queued', 'in_progress'))
     );
end $$;
revoke all on function public._preempt_normal_claims() from public, anon, authenticated;

-- Same validation as before. A preempted bot may submit while the row is queued, or
-- while toxy-researcher-3 holds the paid/request claim. The payload is inserted as
-- sent. If nobody else holds the firm, a valid submit still marks it submitted. If
-- researcher 3 already holds it, that claim stays. An invalid dump from the preempted
-- bot is stored and does not burn attempts or drop the paid claim.
create or replace function public.research_submit(p_id text, p_bot text, p_payload jsonb, p_count int, p_valid boolean, p_errors jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  q research_queue;
  s_id bigint;
  v_holder boolean;
  v_prior boolean;
begin
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

create or replace function public.research_claim(p_bot text, p_count integer)
returns setof research_queue
language plpgsql security definer set search_path = public as $$
declare r research_queue;
begin
  -- a paid or request job takes the firm now; a normal claim with no such job still waits out the 6h expiry below
  perform _preempt_normal_claims();
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
       where q.registry_id = (select rq.registry_id from research_queue rq
                              where rq.status='queued' and rq.lane in ('paid', 'request') and (rq.retry_after is null or rq.retry_after <= now())
                              -- 1) paid checks (an open job with a credit spend), 2) other paid-lane jobs (linked firm
                              -- requests), 3) new-firm requests (lane 'request'); oldest first within each
                              order by case when rq.lane = 'request' then 2
                                            when exists (select 1 from ondemand_jobs oj join research_requests rr on rr.job_id = oj.id
                                                          where oj.registry_id = rq.registry_id and oj.status in ('queued','in_progress')
                                                            and rr.spend_kind is distinct from 'request') then 0 else 1 end,
                                       rq.paid_at nulls last, rq.priority, rq.registry_id
                              limit 1 for update of rq skip locked)
      returning q.*
    loop
      if r.lane = 'request' then return next r; continue; end if;
      with j as (update ondemand_jobs set status = 'in_progress', claimed_at = now(), claimed_by = p_bot
                 where registry_id = r.registry_id and status in ('queued', 'in_progress') returning id)
      update research_requests set status = 'in_progress' where status = 'queued' and job_id in (select id from j);
      return next r;
    end loop;
    return;  -- requested firms only: never normal-lane work
  end if;
  return query
  update research_queue q set status='claimed', claimed_by=p_bot, claimed_at=now(), updated_at=now()
   where q.registry_id in (select registry_id from research_queue
                            where status='queued' and lane = 'normal' and (retry_after is null or retry_after <= now())
                            order by priority limit greatest(1, least(p_count,300)) for update skip locked)
  returning q.*;
end $$;

-- Filing a paid job releases a normal claim on that firm in the same transaction.
create or replace function public._ondemand_enqueue(p_firm uuid, p_qid text, p_balance uuid, p_kind text, p_email text, p_anon uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare j ondemand_jobs; q research_queue; front int; em text := lower(nullif(btrim(coalesce(p_email, '')), ''));
begin
  if em is not null and em !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then em := null; end if;
  select * into q from research_queue where registry_id = p_qid for update;
  select * into j from ondemand_jobs where firm_id = p_firm and status in ('queued', 'in_progress') for update;
  if j.id is null then
    insert into ondemand_jobs (firm_id, registry_id, status, missing_checks, claimed_at, claimed_by)
    values (p_firm, p_qid, case when q.status = 'claimed' and q.claimed_by = 'toxy-researcher-3' then 'in_progress' else 'queued' end,
            _ondemand_missing(p_firm), case when q.status = 'claimed' and q.claimed_by = 'toxy-researcher-3' then q.claimed_at end,
            case when q.status = 'claimed' and q.claimed_by = 'toxy-researcher-3' then q.claimed_by end)
    returning * into j;
  else
    update ondemand_jobs set missing_checks = _ondemand_missing(p_firm) where id = j.id;
  end if;
  if p_balance is null then
    update research_requests set email = coalesce(email, em)
     where id = (
       select id from research_requests
        where job_id = j.id and spend_kind = p_kind
          and (
            (auth.uid() is not null and user_id = auth.uid())
            or (auth.uid() is null and p_anon is not null and anon_id = p_anon)
            or (em is not null and email is not null and lower(email) = em)
          )
        order by (email is not null) desc, id desc limit 1);
    if not found then
      insert into research_requests (job_id, firm_id, balance_id, user_id, anon_id, email, status, spend_kind)
      values (j.id, p_firm, null, auth.uid(), case when auth.uid() is null then p_anon end, em,
              case when j.status = 'in_progress' then 'in_progress' else 'queued' end, p_kind);
    end if;
  else
    insert into research_requests (job_id, firm_id, balance_id, user_id, anon_id, email, status, spend_kind)
    values (j.id, p_firm, p_balance, auth.uid(), case when auth.uid() is null then p_anon end, em,
            case when j.status = 'in_progress' then 'in_progress' else 'queued' end, p_kind)
    on conflict (job_id, balance_id) do update set email = coalesce(research_requests.email, excluded.email);
  end if;
  select min(priority) into front from research_queue where status = 'queued' and registry_id <> p_qid;
  update research_queue set lane = 'paid', paid_at = coalesce(paid_at, now()),
    priority = least(priority, coalesce(front, priority + 1) - 1), bumped_at = now(),
    status = case when status = 'claimed' then status else 'queued' end,
    attempts = case when status in ('claimed', 'queued') then attempts else 0 end,
    retry_after = case when status = 'claimed' then retry_after else null end,
    claimed_by = case when status = 'claimed' then claimed_by end,
    claimed_at = case when status = 'claimed' then claimed_at end,
    updated_at = now()
  where registry_id = p_qid;
  perform _preempt_normal_claims();
  return j.id;
end $$;
revoke all on function public._ondemand_enqueue(uuid, text, uuid, text, text, uuid) from public, anon, authenticated;

create or replace function public._firm_request_file(p_request bigint)
returns text language plpgsql security definer set search_path = public as $$
declare fr firm_requests; rid text;
begin
  select * into fr from firm_requests where id = p_request;
  if fr.id is null or fr.status <> 'open' then return null; end if;
  rid := 'req-' || fr.id;
  insert into research_queue (registry_id, name, website, priority, status, lane, paid_at, list_source)
  values (rid, fr.name, fr.website, 0, 'queued', 'request', fr.created_at, 'firm_request')
  on conflict (registry_id) do nothing;
  perform _preempt_normal_claims();
  return rid;
end $$;
revoke all on function public._firm_request_file(bigint) from public, anon, authenticated;

-- Same as 20261025005949, plus a release if this signup's queue row is held by a normal claim.
create or replace function public._check_request_file(p_id bigint) returns bigint
language plpgsql security definer set search_path = public as $$
declare c check_requests; fid uuid; qid text; em text; jid bigint; rid bigint; reg text; qn text;
begin
  select * into c from check_requests where id = p_id for update;
  if c.id is null or c.research_request_id is not null then return c.research_request_id; end if;
  em := lower(nullif(btrim(coalesce(c.email, '')), ''));
  if em is not null and em !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then em := null; end if;
  fid := c.firm_id;
  if fid is not null then qid := _firm_queue_id(fid); end if;
  if fid is not null and em is not null then
    select r.id, r.job_id into rid, jid from research_requests r
     where r.firm_id = fid and r.email is not null and lower(r.email) = em
     order by (r.status in ('queued', 'in_progress')) desc, r.id desc limit 1;
  end if;
  if rid is null and fid is not null and qid is not null and _ondemand_needed(fid) then
    jid := _ondemand_enqueue(fid, qid, null, 'request', em, c.anon_id);
    select r.id into rid from research_requests r
     where r.job_id = jid and r.spend_kind = 'request'
       and ((em is not null and lower(r.email) is not distinct from em) or (em is null and r.email is null)
            or (auth.uid() is null and c.anon_id is not null and r.anon_id = c.anon_id))
     order by r.id desc limit 1;
  elsif rid is null and fid is not null and qid is not null and em is not null and not _ondemand_needed(fid) then
    insert into ondemand_jobs (firm_id, registry_id, status, done_at)
    values (fid, qid, 'done', now()) returning id into jid;
    insert into research_requests (job_id, firm_id, balance_id, user_id, anon_id, email, status, spend_kind, done_at)
    values (jid, fid, null, c.user_id, c.anon_id, em, 'done', 'request', now()) returning id into rid;
  elsif fid is null then
    reg := 'req-' || c.id::text;
    if exists (select 1 from research_queue where registry_id = reg and coalesce(list_source, '') is distinct from 'check_request') then
      reg := 'req-c' || c.id::text;
    end if;
    qn := left(regexp_replace(btrim(coalesce(c.query, '')), '\s+', ' ', 'g'), 200);
    if length(qn) >= 1 then
      insert into research_queue (registry_id, name, priority, status, lane, paid_at, list_source)
      values (reg, qn, 0, 'queued', 'request', c.created_at, 'check_request')
      on conflict (registry_id) do nothing;
    end if;
  end if;
  perform _preempt_normal_claims();
  if rid is not null then
    update research_requests set user_id = coalesce(user_id, c.user_id),
      anon_id = coalesce(anon_id, c.anon_id), email = coalesce(email, em) where id = rid;
    update check_requests set research_request_id = rid, job_id = coalesce(jid, job_id),
      notified_at = coalesce(notified_at, now()),
      status = case when (select status from research_requests where id = rid) = 'done' then 'done' else status end
     where id = c.id;
    update research_queue set status = 'skipped', lane = 'normal', paid_at = null,
      last_error = 'check request linked', updated_at = now()
     where list_source = 'check_request' and status = 'queued'
       and registry_id in ('req-' || c.id::text, 'req-c' || c.id::text);
  end if;
  return rid;
end $$;
revoke all on function public._check_request_file(bigint) from public, anon, authenticated;

-- Firms already held when this ships (paid job open, normal bot still claimed).
select public._preempt_normal_claims();
