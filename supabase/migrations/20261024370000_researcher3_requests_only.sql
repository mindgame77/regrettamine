-- toxy-researcher-3 handles only requested firms (Alex, Oct 24 2026):
--  * revert the PR #112 fall-through: with no request waiting, Researcher 3 gets nothing (other bots unchanged);
--  * claim order: paid checks (credit spends) first, then "Request this firm" requests, each oldest first;
--  * a new "Request this firm" request now files its own queue row right away: registry_id 'req-<request id>',
--    lane 'request', list_source 'firm_request'. Only Researcher 3 claims that lane. No page is made until the
--    research lands (valid submission): then the request is linked (zz_firm_request_done) and the requesters get the
--    usual ready_request email (or a paid-lane job if checks are still missing). Emails and raw data unchanged.
ALTER TABLE public.research_queue DROP CONSTRAINT research_queue_lane_chk;
ALTER TABLE public.research_queue ADD CONSTRAINT research_queue_lane_chk CHECK (lane = ANY (ARRAY['normal'::text, 'paid'::text, 'request'::text]));

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
end $function$;

-- no 'Not checked yet' page for a request-lane row: the page is made when its research lands
CREATE OR REPLACE FUNCTION public.research_queue_page_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.duplicate_of is not null or new.status = 'skipped' or new.lane = 'request' then return null; end if;
  begin
    perform ensure_firm_for_registry(new.registry_id, false);
  exception when others then
    raise warning 'research_queue_page %: %', new.registry_id, sqlerrm;  -- never block a queue insert
  end;
  return null;
end $function$;

-- a request-lane row is linked after its research lands (unless the dedupe trigger already points it at a known firm)
CREATE OR REPLACE FUNCTION public.firm_request_link_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r firm_requests; d text := _req_domain(new.website);
begin
  if new.lane = 'request' and new.duplicate_of is null then return null; end if;
  for r in select * from firm_requests where status = 'open'
            and (name_key = _queue_name_key(new.name) or (d is not null and website_domain = d)) loop
    begin
      perform firm_request_link(r.id, new.registry_id);
    exception when others then raise warning 'firm_request_link_trg % -> %: %', r.id, new.registry_id, sqlerrm;  -- never block a queue insert
    end;
  end loop;
  return null;
end $function$;

-- when a request gets linked to another queue row (a list builder added the firm), its own request-lane row is dropped
CREATE OR REPLACE FUNCTION public.firm_request_link(p_request bigint, p_registry text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare fr firm_requests; t text; fid uuid; n int;
begin
  select * into fr from firm_requests where id = p_request for update;
  if fr.id is null then return json_build_object('status', 'error', 'error', 'unknown request'); end if;
  select coalesce(duplicate_of, registry_id) into t from research_queue where registry_id = p_registry;
  if t is null then return json_build_object('status', 'error', 'error', 'unknown registry_id'); end if;
  if fr.status = 'linked' and fr.registry_id = t then
    n := _firm_request_enqueue(fr.id);
    return json_build_object('status', 'ok', 'registry_id', t, 'filed', n, 'already_linked', true);
  end if;
  begin perform ensure_firm_for_registry(t, false); exception when others then raise warning 'firm_request_link %: %', t, sqlerrm; end;
  select id into fid from firms where registry_id = t and deleted_at is null order by created_at limit 1;
  if fid is null then return json_build_object('status', 'error', 'error', 'no firm page for this registry_id yet'); end if;
  update firm_requests set status = 'linked', registry_id = t, firm_id = fid, linked_at = now(), updated_at = now() where id = fr.id;
  update research_queue set status = 'skipped', last_error = 'firm request linked to ' || t, updated_at = now()
   where registry_id = 'req-' || fr.id and registry_id <> t and lane = 'request' and status = 'queued';
  n := _firm_request_enqueue(fr.id);
  return json_build_object('status', 'ok', 'registry_id', t, 'firm_id', fid, 'filed', n);
end $function$;

-- file an open request into research_queue (idempotent): registry_id 'req-<id>', lane 'request'
CREATE OR REPLACE FUNCTION public._firm_request_file(p_request bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare fr firm_requests; rid text;
begin
  select * into fr from firm_requests where id = p_request;
  if fr.id is null or fr.status <> 'open' then return null; end if;
  rid := 'req-' || fr.id;
  insert into research_queue (registry_id, name, website, priority, status, lane, paid_at, list_source)
  values (rid, fr.name, fr.website, 0, 'queued', 'request', fr.created_at, 'firm_request')
  on conflict (registry_id) do nothing;
  return rid;
end $function$;
REVOKE ALL ON FUNCTION public._firm_request_file(bigint) FROM public, anon, authenticated;

-- research for a request-lane row landed: the page now exists, link the request (ready_request email or paid-lane job
-- for still-missing checks, via _firm_request_enqueue) and move the row to the normal lane. Fires before zz_ondemand_done.
CREATE OR REPLACE FUNCTION public.firm_request_done_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare q research_queue; v_req bigint;
begin
  if not new.valid or new.registry_id !~ '^req-[0-9]+$' then return null; end if;
  begin
    select * into q from research_queue where registry_id = new.registry_id;
    if q.lane is distinct from 'request' then return null; end if;
    v_req := substring(new.registry_id from 5)::bigint;
    if (select status from firm_requests where firm_requests.id = v_req) = 'open' then perform firm_request_link(v_req, new.registry_id); end if;
    update research_queue set lane = 'normal', paid_at = null, updated_at = now() where registry_id = new.registry_id and lane = 'request';
  exception when others then
    raise warning 'firm_request_done: submission % registry %: %', new.id, new.registry_id, sqlerrm;  -- never block an ingest
  end;
  return null;
end $function$;
DROP TRIGGER IF EXISTS zz_firm_request_done ON public.research_submissions;
CREATE TRIGGER zz_firm_request_done AFTER INSERT ON public.research_submissions FOR EACH ROW EXECUTE FUNCTION firm_request_done_trg();

CREATE OR REPLACE FUNCTION public.request_firm(p_name text, p_email text, p_website text DEFAULT NULL::text, p_anon uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare nm text := left(regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g'), 150);
  k text := _queue_name_key(nm); em text := lower(btrim(coalesce((select email from auth.users where id = auth.uid()), p_email, '')));
  web text := nullif(btrim(coalesce(p_website, '')), ''); dom text; h text := _ip_hash(); fr firm_requests; f firms; dup boolean;
begin
  if auth.uid() is null and p_anon is null then return json_build_object('status', 'no_visitor'); end if;
  if em !~* '^[a-z0-9._%+''-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$' or length(em) > 200 then return json_build_object('status', 'bad_email'); end if;
  if length(nm) < 2 or nm !~ '[[:alpha:]]' or length(coalesce(k, '')) < 2 or nm ~* '(https?://|<|>)' then return json_build_object('status', 'bad_name'); end if;
  if web is not null then
    dom := _req_domain(web);
    if dom is null or length(web) > 300 then return json_build_object('status', 'bad_website'); end if;
  end if;
  -- rate limits: 5 per visitor (anon id / account) per hour, 5 per IP per hour, 3 per email per day, 300 site-wide per hour
  if (select count(*) from firm_request_emails where created_at > now() - interval '1 hour'
       and ((auth.uid() is not null and user_id = auth.uid()) or (p_anon is not null and anon_id = p_anon))) >= 5
     or (h is not null and (select count(*) from firm_request_emails where created_at > now() - interval '1 hour' and ip_hash = h) >= 5)
     or (select count(*) from firm_request_emails where created_at > now() - interval '1 day' and lower(email) = em) >= 3
     or (select count(*) from firm_request_emails where created_at > now() - interval '1 hour') >= 300 then
    return json_build_object('status', 'rate_limited');
  end if;
  f := _firm_by_name_key(k);
  if f.id is not null then return json_build_object('status', 'exists', 'slug', f.slug); end if;
  insert into firm_requests (name, name_key, website, website_domain) values (nm, k, case when dom is not null then web end, dom)
    on conflict (name_key) do update set updated_at = now(),
      website = coalesce(firm_requests.website, excluded.website), website_domain = coalesce(firm_requests.website_domain, excluded.website_domain)
    returning * into fr;
  dup := exists (select 1 from firm_request_emails where request_id = fr.id and lower(email) = em);
  if not dup then
    insert into firm_request_emails (request_id, email, anon_id, user_id, ip_hash, website)
      values (fr.id, em, case when auth.uid() is null then p_anon end, auth.uid(), h, web);
    -- already linked (a list builder added it meanwhile): this requester joins the open job right away
    if fr.status = 'linked' and fr.registry_id is not null then perform _firm_request_enqueue(fr.id); end if;
  end if;
  -- still open: file it into the queue now (lane 'request') so Researcher 3 picks it up after paid checks
  if fr.status = 'open' then
    begin perform _firm_request_file(fr.id); exception when others then raise warning 'request_firm file %: %', fr.id, sqlerrm; end;
  end if;
  return json_build_object('status', 'ok', 'already_requested', dup, 'state', fr.status);
end $function$;

-- backfill: any request still open goes into the queue now
do $$ declare i bigint; begin
  for i in select id from firm_requests where status = 'open' order by created_at loop perform _firm_request_file(i); end loop;
end $$;
