-- Sprint step 4: paid on-demand research.
-- 'Check with 1 credit' on an unchecked page or a published partial page (any check 'Not checked yet') spends 1 credit
-- (same free / signed-in rules as before) and files a research_request. One ondemand_job per firm while open; every
-- requester is linked to it. The queue entry moves to the paid lane (research_queue.lane = 'paid', front of the queue),
-- which only the dedicated bot 'toxy-researcher-3' claims (one at a time, oldest paid first) through the existing
-- research-ingest claim/submit actions (docs/ON_DEMAND.md). A valid submission (after aa_ensure_firm) marks the job and
-- its requests done; the requester keeps the page (the spend event is the unlock). Not done within 24 h: the credit is
-- refunded (check_events 'refund_ondemand') and the requester is emailed. Emails go through the ondemand-notify Edge
-- Function (Resend), kicked by pg_cron + pg_net every 2 minutes.
-- Page views no longer reorder the queue: bump_firm_check keeps its signature but never changes priority; only paid
-- requests and request-a-check form submits (request_check) move a firm forward.
-- Backup: /workspace/backups/pre-ondemand-2026-10-24/

alter table public.research_queue add column if not exists lane text not null default 'normal';
alter table public.research_queue add column if not exists paid_at timestamptz;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'research_queue_lane_chk') then
    alter table public.research_queue add constraint research_queue_lane_chk check (lane in ('normal', 'paid'));
  end if;
end $$;
comment on column public.research_queue.lane is '''paid'' = someone spent a credit for this firm (on-demand research). Claimed only by toxy-researcher-3, oldest paid_at first.';
create index if not exists research_queue_paid_idx on public.research_queue (paid_at) where lane = 'paid' and status = 'queued';

alter table public.check_events drop constraint if exists check_events_kind_check;
alter table public.check_events add constraint check_events_kind_check check (kind = any (array['spend_free', 'spend_paid', 'grant_signup',
  'grant_single', 'grant_plan', 'grant_refill', 'refund_ondemand']));

create table if not exists public.ondemand_jobs (
  id bigserial primary key,
  firm_id uuid not null references public.firms(id) on delete cascade,
  registry_id text not null references public.research_queue(registry_id),
  status text not null default 'queued' check (status in ('queued', 'in_progress', 'done', 'refunded')),
  missing_checks jsonb not null default '[]',
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  claimed_by text,
  done_at timestamptz,
  submission_id bigint
);
comment on table public.ondemand_jobs is 'One paid research job per firm while open (queued / in_progress); all requesters link to it (research_requests.job_id).';
create unique index if not exists ondemand_jobs_open_key on public.ondemand_jobs (firm_id) where status in ('queued', 'in_progress');
create index if not exists ondemand_jobs_registry_idx on public.ondemand_jobs (registry_id);

create table if not exists public.research_requests (
  id bigserial primary key,
  job_id bigint not null references public.ondemand_jobs(id) on delete cascade,
  firm_id uuid not null references public.firms(id) on delete cascade,
  balance_id uuid not null references public.check_balances(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  anon_id uuid,
  email text check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  status text not null default 'queued' check (status in ('queued', 'in_progress', 'done', 'refunded')),
  spend_kind text not null check (spend_kind in ('spend_free', 'spend_paid')),
  created_at timestamptz not null default now(),
  done_at timestamptz,
  refunded_at timestamptz,
  notified_at timestamptz,
  notify_error text
);
comment on table public.research_requests is 'Who paid 1 credit for on-demand research on a firm (account or anon id), optional email, status queued/in_progress/done/refunded.';
create unique index if not exists research_requests_job_balance_key on public.research_requests (job_id, balance_id);
create index if not exists research_requests_open_idx on public.research_requests (created_at) where status in ('queued', 'in_progress');
create index if not exists research_requests_firm_idx on public.research_requests (firm_id);
alter table public.ondemand_jobs enable row level security;
alter table public.research_requests enable row level security;
revoke all on public.ondemand_jobs, public.research_requests from anon, authenticated;

-- Checks still 'Not checked yet' on a firm: [{n, title}] (the job lists them for the bot).
create or replace function public._ondemand_missing(p_firm uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('n', n, 'title', title) order by n), '[]') from firm_check_rows where firm_id = p_firm and state = 'nc'
$$;

-- Does this firm still need research? Unchecked page, or any check 'Not checked yet'.
create or replace function public._ondemand_needed(p_firm uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from firms where id = p_firm and not indexable)
      or exists (select 1 from firm_check_rows where firm_id = p_firm and state = 'nc')
$$;

-- File one request (after the credit was spent): join the open job for the firm or open one, move the queue entry to the paid lane.
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
  insert into research_requests (job_id, firm_id, balance_id, user_id, anon_id, email, status, spend_kind)
  values (j.id, p_firm, p_balance, auth.uid(), case when auth.uid() is null then p_anon end, em,
          case when j.status = 'in_progress' then 'in_progress' else 'queued' end, p_kind)
  on conflict (job_id, balance_id) do update set email = coalesce(research_requests.email, excluded.email);
  -- front of the queue, paid lane; a firm another bot is working on right now is left with that bot
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
  return j.id;
end $$;

-- What the page shows: this visitor's latest request on the firm (requesters see 'Research in progress').
create or replace function public._ondemand_view(p_firm uuid, p_anon uuid) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('status', r.status, 'mine', true, 'email', r.email is not null, 'created_at', r.created_at,
                           'missing', (select count(*) from jsonb_array_elements(j.missing_checks)))
  from research_requests r join ondemand_jobs j on j.id = r.job_id
  where r.firm_id = p_firm and ((auth.uid() is not null and r.user_id = auth.uid()) or (auth.uid() is null and p_anon is not null and r.anon_id = p_anon))
  order by r.id desc limit 1
$$;

-- Unlock: unchanged credit rules. New: an unchecked or partial page spends 1 credit and files a research request.
-- A refunded on-demand credit takes the unlock back (spends minus refunds per firm).
CREATE OR REPLACE FUNCTION public.unlock_firm(p_slug text, p_anon uuid, p_spend boolean DEFAULT true)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b public.check_balances := _balance(p_anon); f uuid; ix boolean; h text := _ip_hash(); ip_cap constant int := 4;
  need boolean; qid text; sk text; em text;
begin
  select id, indexable into f, ix from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f is null then return json_build_object('status','not_found'); end if;
  if coalesce((select sum(case when kind like 'spend_%' then 1 when kind = 'refund_ondemand' then -1 else 0 end) from check_events
               where balance_id = b.id and firm_id = f), 0) <= 0 then
    if not p_spend then return json_build_object('status','locked'); end if;
    need := _ondemand_needed(f);
    if need then qid := _firm_queue_id(f); end if;
    -- 'Not checked yet' page with no research queue entry: nothing to research; send the visitor to the request-a-check form.
    if not ix and qid is null then return json_build_object('status','unchecked'); end if;
    if b.free_left > 0 and auth.uid() is null and h is not null
       and (select count(*) from check_events where ip_hash = h and kind = 'spend_free' and created_at > now() - interval '30 days') >= ip_cap then
      return json_build_object('status','need_signup');
    end if;
    if b.free_left > 0 then
      update check_balances set free_left = free_left - 1, updated_at = now() where id = b.id;
      insert into check_events(balance_id, firm_id, kind, amount, ip_hash) values (b.id, f, 'spend_free', -1, case when auth.uid() is null then h end);
      sk := 'spend_free';
    elsif b.paid_left > 0 then
      update check_balances set paid_left = paid_left - 1, updated_at = now() where id = b.id;
      insert into check_events(balance_id, firm_id, kind, amount) values (b.id, f, 'spend_paid', -1);
      sk := 'spend_paid';
    elsif auth.uid() is null then return json_build_object('status','need_signup');
    else return json_build_object('status','out');
    end if;
    if need and qid is not null then
      em := (select email from auth.users where id = auth.uid());
      perform _ondemand_enqueue(f, qid, b.id, sk, em, p_anon);
    end if;
  end if;
  return json_build_object('status','ok','details', public.firm_details(f));
end $function$
;

CREATE OR REPLACE FUNCTION public.firm_page(p_slug text, p_anon uuid, p_spend boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f firms; u json; open boolean; secs jsonb := '[]'; s page_sections; it jsonb; hero jsonb; q research_queue; qid text;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  u := unlock_firm(p_slug, p_anon, p_spend);
  open := u->>'status' = 'ok';
  if u->>'status' not in ('ok', 'locked') then return u; end if;
  if not open then
    -- Locked (blur A): only what every visitor may see: the firm, the SEC hero facts, the 10 check names and the progress count.
    -- No section list, counts, teasers, outline, states, counts or dates of any check; firm_details only on an unlocked page.
    select coalesce(jsonb_agg(jsonb_build_object('label', hero_label, 'value', hero_value, 'anchor', section,
        'src', _src('firm_profile_facts', id)) order by section desc, sort_order), '[]') into hero
      from firm_profile_facts where firm_id = f.id and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
    qid := _firm_queue_id(f.id);
    if qid is not null then select * into q from research_queue where registry_id = qid; end if;
    if not f.indexable and jsonb_array_length(hero) = 0 then
      -- 'Not checked yet' page: registration facts from the research queue row (no source chips: nothing checked yet)
      select coalesce(jsonb_agg(jsonb_build_object('label', l, 'value', v, 'anchor', 'overview', 'src', '[]'::jsonb) order by o), '[]') into hero
        from (values (1, 'HQ', f.hq), (2, 'SEC CRD', nullif(q.sec_crd, '')), (3, 'LEI', nullif(q.lei, ''))) x(o, l, v) where v is not null;
    end if;
    return json_build_object('status', 'ok', 'open', false, 'locked', u->>'status', 'unchecked', not f.indexable,
      'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', f.hq),
      'hero', hero, 'sections', '[]'::json, 'done', _firm_checks_done(f.id),
      'checks', (select json_agg(json_build_object('n', n, 'title', title, 'descr', descr, 'state', null, 'count', null, 'searched_at', null,
          'items', null, 'itemized', null) order by n) from firm_check_rows where firm_id = f.id),
      'queue', q.status, 'started_at', case when q.status = 'claimed' then q.claimed_at end, 'details', null, 'outline', null,
      'ondemand', _ondemand_view(f.id, p_anon));
  end if;
  for s in select * from page_sections where enabled order by sort_order loop
    it := _sec_items(s.key, f.id);
    continue when jsonb_array_length(it) = 0;
    secs := secs || jsonb_build_object('key', s.key, 'title', s.title, 'subtitle', s.subtitle, 'renderer', s.renderer,
      'count', jsonb_array_length(it), 'unit', case when jsonb_array_length(it) = 1 then s.unit_one else s.unit_many end,
      'teaser', it->0->>'head', 'items', it);
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('label', hero_label, 'value', hero_value, 'anchor', section,
      'src', _src('firm_profile_facts', id)) order by section desc, sort_order), '[]') into hero
    from firm_profile_facts where firm_id = f.id and hero_label is not null and exists (select 1 from fact_sources where fact_type = 'firm_profile_facts' and fact_id = firm_profile_facts.id);
  qid := _firm_queue_id(f.id);
  if qid is not null then select * into q from research_queue where registry_id = qid; end if;
  return json_build_object('status', 'ok', 'open', true, 'unchecked', false, 'done', _firm_checks_done(f.id),
    'firm', json_build_object('slug', f.slug, 'name', coalesce(f.display_name, f.name), 'sec_name', coalesce(f.legal_name, f.name), 'short_name', f.short_name, 'hq', f.hq),
    'hero', hero, 'sections', secs,
    'checks', (select json_agg(json_build_object('n', n, 'title', title, 'descr', descr, 'state', state, 'count', count_label, 'searched_at', searched_at,
        'items', (select coalesce(json_agg(json_build_object('title', i.title, 'year', i.yr, 'status', i.status, 'note', i.note, 'who', i.who) order by i.yr desc nulls last, i.title), '[]') from check_findings(source_submission) i where i.k = n),
        'itemized', (select count(*) from check_findings(source_submission) i where i.k = n)) order by n) from firm_check_rows where firm_id = f.id),
    'queue', q.status, 'started_at', case when q.status = 'claimed' then q.claimed_at end,
    'details', u->'details', 'outline', null, 'ondemand', _ondemand_view(f.id, p_anon));
end $function$
;

-- Claim: 'toxy-researcher-3' (the Regretamin Researcher 3) takes paid jobs only, one at a time, oldest paid first.
-- Every other bot never sees the paid lane.
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
                            order by priority limit greatest(1, least(p_count,5)) for update skip locked)
  returning q.*;
end $function$
;

-- Job details for claimed registry ids (research-ingest adds them to the claim response): paid flag, job id, missing checks.
create or replace function public.ondemand_job_info(p_ids text[]) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(j.registry_id, jsonb_build_object('ondemand_job_id', j.id, 'paid', true,
           'missing_checks', _ondemand_missing(j.firm_id), 'requesters', (select count(*) from research_requests r where r.job_id = j.id),
           'requested_at', j.created_at, 'refund_at', j.created_at + interval '24 hours')), '{}')
  from ondemand_jobs j where j.registry_id = any(p_ids) and j.status in ('queued', 'in_progress')
$$;

-- Valid research arrived (runs after aa_ensure_firm / checks_from_upload / promote_bot_facts): job + requests done, back to the normal lane.
create or replace function public.ondemand_done_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare t text;
begin
  if not new.valid then return null; end if;
  begin
    t := coalesce(_registry_target(new.registry_id), new.registry_id);
    with j as (update ondemand_jobs set status = 'done', done_at = now(), submission_id = new.id,
                 missing_checks = _ondemand_missing(firm_id)
               where registry_id in (t, new.registry_id) and status in ('queued', 'in_progress') returning id)
    update research_requests set status = 'done', done_at = now() where job_id in (select id from j) and status in ('queued', 'in_progress');
    update research_queue set lane = 'normal', paid_at = null where registry_id in (t, new.registry_id) and lane = 'paid';
  exception when others then
    raise warning 'ondemand_done: submission % registry %: %', new.id, new.registry_id, sqlerrm;  -- never block an ingest
  end;
  return null;
end $$;
drop trigger if exists zz_ondemand_done on public.research_submissions;
create trigger zz_ondemand_done after insert on public.research_submissions for each row execute function public.ondemand_done_trg();

-- 24 h without valid research: give the credit back (same bucket it came from) and close the request.
create or replace function public.ondemand_refund_expired() returns int
language plpgsql security definer set search_path = public as $$
declare rq research_requests; n int := 0;
begin
  for rq in select * from research_requests where status in ('queued', 'in_progress') and created_at < now() - interval '24 hours'
           order by id for update skip locked loop
    if rq.spend_kind = 'spend_free' then update check_balances set free_left = free_left + 1, updated_at = now() where id = rq.balance_id;
    else update check_balances set paid_left = paid_left + 1, updated_at = now() where id = rq.balance_id; end if;
    insert into check_events (balance_id, firm_id, kind, amount) values (rq.balance_id, rq.firm_id, 'refund_ondemand', 1);
    update research_requests set status = 'refunded', refunded_at = now() where id = rq.id;
    n := n + 1;
  end loop;
  update ondemand_jobs j set status = 'refunded' where status in ('queued', 'in_progress')
     and not exists (select 1 from research_requests x where x.job_id = j.id and x.status in ('queued', 'in_progress'));
  update research_queue q set lane = 'normal', paid_at = null where q.lane = 'paid'
     and not exists (select 1 from ondemand_jobs o where o.registry_id = q.registry_id and o.status in ('queued', 'in_progress'));
  return n;
end $$;

-- Email outbox for ondemand-notify: 'ready' (done) and 'refund' (refunded), each request once, only with an email.
create or replace function public.ondemand_outbox(p_limit int default 50)
returns table(id bigint, kind text, email text, name text, slug text)
language sql stable security definer set search_path = public as $$
  select r.id, case when r.status = 'done' then 'ready' else 'refund' end, r.email, coalesce(f.display_name, f.name), f.slug
  from research_requests r join firms f on f.id = r.firm_id
  where r.status in ('done', 'refunded') and r.email is not null and r.notified_at is null and r.notify_error is null
  order by r.id limit greatest(1, least(coalesce(p_limit, 50), 200))
$$;
create or replace function public.ondemand_mark_notified(p_id bigint, p_error text default null) returns void
language sql security definer set search_path = public as $$
  update research_requests set notified_at = case when p_error is null then now() end, notify_error = left(p_error, 500) where id = p_id;
$$;

-- Shared key between pg_cron and ondemand-notify, kept in Supabase Vault (never leaves the database).
create or replace function public.ondemand_cron_ok(p_key text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare k text;
begin
  execute 'select decrypted_secret from vault.decrypted_secrets where name = ''ondemand_cron_key'' limit 1' into k;
  return k is not null and p_key is not null and k = p_key;
exception when others then return false;
end $$;

-- Every 2 minutes (pg_cron): refunds, then kick ondemand-notify (pg_net) when an email is waiting.
create or replace function public.ondemand_tick() returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int := ondemand_refund_expired(); k text; req bigint;
begin
  if exists (select 1 from ondemand_outbox(1)) and exists (select 1 from pg_extension where extname = 'pg_net') then
    begin
      execute 'select decrypted_secret from vault.decrypted_secrets where name = ''ondemand_cron_key'' limit 1' into k;
      execute 'select net.http_post(url := $1, body := ''{}''::jsonb, headers := jsonb_build_object(''content-type'', ''application/json'', ''x-ondemand-key'', $2))'
        into req using 'https://sxxgvkdwgiouyqciztec.supabase.co/functions/v1/ondemand-notify', k;
    exception when others then raise warning 'ondemand_tick: %', sqlerrm;
    end;
  end if;
  return jsonb_build_object('refunded', n, 'notify_request', req);
end $$;

-- Signed-out requester leaves an email on the page (existing 'Email me when it's ready' box): attach it to the open request.
CREATE OR REPLACE FUNCTION public.notify_when_checked(p_slug text, p_email text, p_anon uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f firms; em text;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  em := lower(trim(coalesce((select email from auth.users where id = auth.uid()), p_email, '')));
  if em !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(em) > 200 then return json_build_object('status', 'bad_email'); end if;
  if auth.uid() is null and p_anon is null then return json_build_object('status', 'no_visitor'); end if;
  -- an open paid request by this visitor: the email goes on it (one 'ready' or 'refund' email), not on a second list
  update research_requests set email = em
   where id = (select id from research_requests where firm_id = f.id and status in ('queued', 'in_progress')
                 and ((auth.uid() is not null and user_id = auth.uid()) or (auth.uid() is null and anon_id = p_anon)) order by id desc limit 1);
  if found then return json_build_object('status', 'ok'); end if;
  if exists (select 1 from check_requests where firm_id = f.id and lower(email) = em and notified_at is null) then
    return json_build_object('status', 'ok'); end if;
  if (select count(*) from check_requests where created_at > now() - interval '1 hour'
       and (user_id = auth.uid() or (auth.uid() is null and anon_id = p_anon))) >= 10 then
    return json_build_object('status', 'rate_limited'); end if;
  insert into check_requests (query, email, anon_id, user_id, firm_id, status)
    values (f.name, em, p_anon, auth.uid(), f.id, 'running');
  return json_build_object('status', 'ok');
end $function$
;

-- Page views (people and crawlers) no longer reorder the queue: same signature and answers, never changes priority.
CREATE OR REPLACE FUNCTION public.bump_firm_check(p_slug text, p_anon uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f firms; qid text; q research_queue;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and published and not coalesce(is_test, false) and data_status = 'real';
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  if _firm_checks_done(f.id) >= 10 then return json_build_object('status', 'complete'); end if;
  qid := _firm_queue_id(f.id);
  if qid is null then return json_build_object('status', 'not_in_queue'); end if;
  select * into q from research_queue where registry_id = qid;
  return json_build_object('status', q.status, 'bumped', false);
end $function$
;

-- Request-a-check form: store the request and, when the query names a known firm exactly, move it to the front (normal lane).
CREATE OR REPLACE FUNCTION public.request_check(p_query text, p_email text, p_anon uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t text := lower(btrim(coalesce(p_query, ''))); fid uuid; qid text; front int; rid bigint;
begin
  insert into check_requests(query, email, anon_id, user_id) values (trim(p_query), nullif(trim(p_email),''), p_anon, auth.uid()) returning id into rid;
  if t = '' then return; end if;
  -- at most 10 bumps per visitor per hour
  if (select count(*) from check_requests where created_at > now() - interval '1 hour'
       and ((auth.uid() is not null and user_id = auth.uid()) or (auth.uid() is null and anon_id = p_anon))) > 10 then return; end if;
  select f.id into fid from firms f
   where f.published and f.deleted_at is null and not coalesce(f.is_test, false) and f.data_status = 'real'
     and (lower(coalesce(f.display_name, f.name)) = t or lower(f.name) = t or f.slug = t or lower(coalesce(f.short_name, '')) = t
          or exists (select 1 from firm_aliases a where a.firm_id = f.id and lower(a.alias) = t))
   order by f.indexable, f.id limit 1;
  if fid is null then return; end if;
  update check_requests set firm_id = fid where id = rid;
  qid := _firm_queue_id(fid);
  if qid is null then return; end if;
  select min(priority) into front from research_queue where status = 'queued' and registry_id <> qid;
  update research_queue set priority = front - 1, bumped_at = now(), updated_at = now()
   where registry_id = qid and status = 'queued' and front is not null and priority >= front;
end $function$
;

-- Admin / bot view of the paid lane, in claim order.
create or replace view public.ondemand_queue with (security_invoker = true) as
  select q.registry_id, q.name, q.status as queue_status, q.claimed_by, q.claimed_at, q.paid_at, j.id as job_id, j.status as job_status,
         j.created_at as requested_at, j.created_at + interval '24 hours' as refund_at, j.missing_checks,
         (select count(*) from research_requests r where r.job_id = j.id) as requesters
  from research_queue q join ondemand_jobs j on j.registry_id = q.registry_id and j.status in ('queued', 'in_progress')
  where q.lane = 'paid'
  order by q.paid_at, q.priority, q.registry_id;
revoke all on public.ondemand_queue from anon, authenticated;

revoke all on function public._ondemand_missing(uuid), public._ondemand_needed(uuid), public._ondemand_enqueue(uuid, text, uuid, text, text, uuid),
  public._ondemand_view(uuid, uuid), public.ondemand_job_info(text[]), public.ondemand_done_trg(), public.ondemand_refund_expired(),
  public.ondemand_outbox(int), public.ondemand_mark_notified(bigint, text), public.ondemand_cron_ok(text), public.ondemand_tick() from public, anon, authenticated;

-- Schedule (Supabase only: pg_cron present). Vault key for the cron -> Edge Function call is created once, never printed.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from pg_available_extensions where name = 'pg_net') then
      execute 'create extension if not exists pg_net';
    end if;
    if to_regclass('vault.secrets') is not null then
      execute 'select vault.create_secret(encode(extensions.gen_random_bytes(24), ''hex''), ''ondemand_cron_key'', ''pg_cron -> ondemand-notify'')
               where not exists (select 1 from vault.secrets where name = ''ondemand_cron_key'')';
    end if;
    execute $c$select cron.schedule('regretamin-ondemand-tick', '*/2 * * * *', 'select public.ondemand_tick()')$c$;
  end if;
end $$;
