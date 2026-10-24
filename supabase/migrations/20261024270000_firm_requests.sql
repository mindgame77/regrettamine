-- Sprint step 5: "Request this firm" (search with no results). docs/FIRM_REQUESTS.md.
-- A visitor leaves an email, the firm name and an optional website. One firm_requests row per normalized name
-- (name_key = _queue_name_key); every requester is one firm_request_emails row (one per email). List builders read
-- firm_requests_open (or research-ingest action firm_requests). When they add the firm to research_queue it is linked
-- automatically (same name_key or website domain; or by hand with firm_request_link): the firm goes through the step-4
-- on-demand flow (ondemand_jobs + research_requests with spend_kind 'request', paid lane / toxy-researcher-3) and each
-- requester gets the 'ready' email when the research lands. No credit is spent, so nothing is refunded after 24 h.

create table if not exists public.firm_requests (
  id bigserial primary key,
  name text not null check (length(btrim(name)) between 2 and 150),
  name_key text not null unique,
  website text,
  website_domain text,
  status text not null default 'open' check (status in ('open', 'linked', 'rejected')),
  registry_id text references public.research_queue(registry_id) on delete set null,
  firm_id uuid references public.firms(id) on delete set null,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  linked_at timestamptz
);
create index if not exists firm_requests_open_idx on public.firm_requests (created_at) where status = 'open';
create index if not exists firm_requests_domain_idx on public.firm_requests (website_domain) where status = 'open';

create table if not exists public.firm_request_emails (
  id bigserial primary key,
  request_id bigint not null references public.firm_requests(id) on delete cascade,
  email text not null check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and length(email) <= 200),
  anon_id uuid,
  user_id uuid references auth.users(id) on delete set null,
  ip_hash text,
  website text,
  created_at timestamptz not null default now(),
  received_notified_at timestamptz,
  notify_error text,
  research_request_id bigint
);
create unique index if not exists firm_request_emails_key on public.firm_request_emails (request_id, lower(email));
create index if not exists firm_request_emails_rate_idx on public.firm_request_emails (created_at);
alter table public.firm_requests enable row level security;
alter table public.firm_request_emails enable row level security;
revoke all on public.firm_requests, public.firm_request_emails from anon, authenticated;

-- research_requests: a firm request has no credit (no balance) and is never refunded
alter table public.research_requests alter column balance_id drop not null;
alter table public.research_requests drop constraint if exists research_requests_spend_kind_check;
alter table public.research_requests add constraint research_requests_spend_kind_check check (spend_kind in ('spend_free', 'spend_paid', 'request'));
alter table public.research_requests add column if not exists firm_request_id bigint references public.firm_requests(id) on delete set null;
create unique index if not exists research_requests_request_email_key on public.research_requests (job_id, lower(email)) where spend_kind = 'request';

create or replace function public._req_domain(u text) returns text language sql immutable as $$
  select nullif(substring(lower(btrim(coalesce(u, ''))) from '^(?:https?://)?(?:www\.)?([a-z0-9][a-z0-9.-]*\.[a-z]{2,})(?:[/:?#]|$)'), '') $$;

-- Live firm whose name / display name / alias normalizes to the same key (search said no results, but be safe)
create or replace function public._firm_by_name_key(k text) returns firms language sql stable security definer set search_path = public as $$
  select f.* from firms f
   where f.deleted_at is null and f.published and not coalesce(f.is_test, false) and f.data_status = 'real'
     and (_queue_name_key(f.name) = k or _queue_name_key(f.display_name) = k or _queue_name_key(f.legal_name) = k
          or exists (select 1 from firm_aliases a where a.firm_id = f.id and _queue_name_key(a.alias) = k))
   order by f.indexable desc, f.created_at limit 1 $$;

-- Public RPC (anon + signed in). Returns {status: ok | exists (slug) | bad_email | bad_name | bad_website | rate_limited | no_visitor}.
create or replace function public.request_firm(p_name text, p_email text, p_website text default null, p_anon uuid default null)
returns json language plpgsql security definer set search_path = public as $$
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
  return json_build_object('status', 'ok', 'already_requested', dup, 'state', fr.status);
end $$;
revoke all on function public.request_firm(text, text, text, uuid) from public;
grant execute on function public.request_firm(text, text, text, uuid) to anon, authenticated, service_role;

-- File every not-yet-filed requester of a linked request into the step-4 on-demand flow.
create or replace function public._firm_request_enqueue(p_request bigint) returns int
language plpgsql security definer set search_path = public as $$
declare fr firm_requests; e firm_request_emails; jid bigint; rid bigint; n int := 0; need boolean;
begin
  select * into fr from firm_requests where id = p_request;
  if fr.firm_id is null or fr.registry_id is null then return 0; end if;
  need := _ondemand_needed(fr.firm_id);
  for e in select * from firm_request_emails where request_id = p_request and research_request_id is null order by id for update loop
    if need then
      rid := null;
      select r.id into rid from research_requests r join ondemand_jobs j on j.id = r.job_id
       where j.firm_id = fr.firm_id and j.status in ('queued', 'in_progress') and r.spend_kind = 'request' and lower(r.email) = lower(e.email);
      if rid is null then
        jid := _ondemand_enqueue(fr.firm_id, fr.registry_id, null, 'request', e.email, e.anon_id);
        select id into rid from research_requests where job_id = jid and spend_kind = 'request' and lower(email) = lower(e.email);
      end if;
      if rid is null then
        insert into research_requests (job_id, firm_id, balance_id, user_id, anon_id, email, status, spend_kind)
        select jid, fr.firm_id, null, e.user_id, e.anon_id, e.email, case when j.status = 'in_progress' then 'in_progress' else 'queued' end, 'request'
          from ondemand_jobs j where j.id = jid
        on conflict do nothing returning id into rid;
      end if;
    else
      -- the firm already has its full check: ready right away (a closed job record keeps the history)
      insert into ondemand_jobs (firm_id, registry_id, status, done_at) values (fr.firm_id, fr.registry_id, 'done', now()) returning id into jid;
      insert into research_requests (job_id, firm_id, balance_id, user_id, anon_id, email, status, spend_kind, done_at)
        values (jid, fr.firm_id, null, e.user_id, e.anon_id, e.email, 'done', 'request', now()) returning id into rid;
    end if;
    update research_requests set firm_request_id = p_request, user_id = coalesce(user_id, e.user_id) where id = rid;
    update firm_request_emails set research_request_id = rid where id = e.id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public._firm_request_enqueue(bigint) from public, anon, authenticated;

-- Link a request to a research_queue entry (list builder, by hand or via the trigger below). Makes sure the page exists.
create or replace function public.firm_request_link(p_request bigint, p_registry text) returns json
language plpgsql security definer set search_path = public as $$
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
  n := _firm_request_enqueue(fr.id);
  return json_build_object('status', 'ok', 'registry_id', t, 'firm_id', fid, 'filed', n);
end $$;
revoke all on function public.firm_request_link(bigint, text) from public, anon, authenticated;
grant execute on function public.firm_request_link(bigint, text) to service_role;

-- Auto-link: a new queue entry with the same normalized name or website domain as an open request.
-- Fires after research_queue_page (alphabetical), so the firm page already exists.
create or replace function public.firm_request_link_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare r firm_requests; d text := _req_domain(new.website);
begin
  for r in select * from firm_requests where status = 'open'
            and (name_key = _queue_name_key(new.name) or (d is not null and website_domain = d)) loop
    begin
      perform firm_request_link(r.id, new.registry_id);
    exception when others then raise warning 'firm_request_link_trg % -> %: %', r.id, new.registry_id, sqlerrm;  -- never block a queue insert
    end;
  end loop;
  return null;
end $$;
revoke all on function public.firm_request_link_trg() from public, anon, authenticated;
drop trigger if exists zz_firm_request_link on public.research_queue;
create trigger zz_firm_request_link after insert on public.research_queue for each row execute function public.firm_request_link_trg();

-- List builders: open requests, most wanted first. No emails (privacy). Service role only.
create or replace view public.firm_requests_open with (security_invoker = true) as
  select r.id, r.name, r.name_key, r.website, r.website_domain, count(e.id)::int requesters,
         min(e.created_at) first_requested_at, max(e.created_at) last_requested_at, r.created_at
    from firm_requests r left join firm_request_emails e on e.request_id = r.id
   where r.status = 'open'
   group by r.id
   order by count(e.id) desc, min(e.created_at);
revoke all on public.firm_requests_open from anon, authenticated, public;
grant select on public.firm_requests_open to service_role;
create or replace function public.firm_requests_list(p_limit int default 100) returns setof public.firm_requests_open
language sql stable security definer set search_path = public as $$
  select * from firm_requests_open limit greatest(1, least(coalesce(p_limit, 100), 500)) $$;
revoke all on function public.firm_requests_list(int) from public, anon, authenticated;
grant execute on function public.firm_requests_list(int) to service_role;
-- close a request without adding the firm (out of scope, spam ...)
create or replace function public.firm_request_reject(p_request bigint, p_note text default null) returns void
language sql security definer set search_path = public as $$
  update firm_requests set status = 'rejected', note = left(p_note, 500), updated_at = now() where id = p_request and status = 'open' $$;
revoke all on function public.firm_request_reject(bigint, text) from public, anon, authenticated;
grant execute on function public.firm_request_reject(bigint, text) to service_role;

-- 24 h refunds: only credit-backed requests (spend_free / spend_paid); a firm request just stays in the paid lane until done.
create or replace function public.ondemand_refund_expired() returns int
language plpgsql security definer set search_path = public as $$
declare rq research_requests; n int := 0;
begin
  for rq in select * from research_requests where status in ('queued', 'in_progress') and spend_kind in ('spend_free', 'spend_paid')
             and created_at < now() - interval '24 hours' order by id for update skip locked loop
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

-- Outbox: 'ready' (paid request done), 'ready_request' (firm request done), 'refund' (credit refunded),
-- 'received' (firm request stored; id = firm_request_emails.id, slug null). Live firm pages only for ready/refund.
drop function if exists public.ondemand_outbox(int);
create or replace function public.ondemand_outbox(p_limit int default 50)
returns table(id bigint, kind text, email text, name text, slug text)
language sql stable security definer set search_path = public as $$
  select * from (
    select r.id, case when r.status = 'refunded' then 'refund' when r.spend_kind = 'request' then 'ready_request' else 'ready' end kind,
           r.email, coalesce(f.display_name, f.name) name, f.slug
      from research_requests r join firms f on f.id = r.firm_id
     where r.status in ('done', 'refunded') and r.email is not null and r.notified_at is null and r.notify_error is null
       and f.published and f.deleted_at is null and f.data_status = 'real' and not coalesce(f.is_test, false)
    union all
    select e.id, 'received', e.email, q.name, null::text
      from firm_request_emails e join firm_requests q on q.id = e.request_id
     where e.received_notified_at is null and e.notify_error is null and e.research_request_id is null
       and e.created_at > now() - interval '2 days') x
  order by kind = 'received', id limit greatest(1, least(coalesce(p_limit, 50), 200))
$$;
revoke all on function public.ondemand_outbox(int) from public, anon, authenticated;
grant execute on function public.ondemand_outbox(int) to service_role;

create or replace function public.ondemand_mark_notified(p_id bigint, p_error text default null, p_kind text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_kind = 'received' then
    update firm_request_emails set received_notified_at = case when p_error is null then now() end, notify_error = left(p_error, 500) where id = p_id;
  else
    update research_requests set notified_at = case when p_error is null then now() end, notify_error = left(p_error, 500) where id = p_id;
  end if;
end $$;
drop function if exists public.ondemand_mark_notified(bigint, text);
revoke all on function public.ondemand_mark_notified(bigint, text, text) from public, anon, authenticated;
grant execute on function public.ondemand_mark_notified(bigint, text, text) to service_role;
