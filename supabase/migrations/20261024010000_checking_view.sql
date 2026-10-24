-- "Checking this firm" view (approved design, 2026-10-23).
-- 1) bump_firm_check: a visitor opening /vc/<slug>/ for a firm whose 10 checks are not all done moves the firm's
--    research_queue row to the front (lowest priority number; research_claim orders by priority asc).
--    Idempotent (already at the front = no change), only touches status='queued' rows (never claimed/submitted/etc.),
--    rate-limited per firm+visitor (10 min) and per visitor (20 firms/hour).
-- 2) firm_check_status: light poll RPC; the per-check progress signal is firm_check_rows.state (written by the
--    ingest/sync path per check): any state other than 'nc' = that check is done. All 10 done = check complete.
-- 3) notify_when_checked: "Email me when it's ready" -> check_requests (RLS, no client policies) with firm_id;
--    ready_check_requests (notify-checks Edge Function / Resend) now waits until the firm's 10 checks are done.
alter table public.research_queue add column if not exists bumped_at timestamptz;

create table if not exists public.check_bumps (
  firm_id uuid not null references public.firms(id) on delete cascade,
  visitor text not null,
  at timestamptz not null default now(),
  primary key (firm_id, visitor));
create index if not exists check_bumps_visitor on public.check_bumps (visitor, at);
alter table public.check_bumps enable row level security;
revoke all on public.check_bumps from anon, authenticated, public;

-- A firm's research_queue row: same SEC CRD first, else same normalized name.
create or replace function public._firm_queue_id(p_firm uuid) returns text
language sql stable security definer set search_path = public as $$
  with f as (select * from firms where id = p_firm),
  nm as (select regexp_replace(regexp_replace(lower(x), '\m(llc|l\.?l\.?c|lp|l\.?p|inc|ltd|management|co)\M', '', 'g'), '[^a-z0-9]', '', 'g') k, x from (select name x from f) s)
  select q.registry_id from research_queue q, f
   where (nullif(f.sec_crd, '') is not null and q.sec_crd = f.sec_crd)
      or regexp_replace(regexp_replace(lower(q.name), '\m(llc|l\.?l\.?c|lp|l\.?p|inc|ltd|management|co)\M', '', 'g'), '[^a-z0-9]', '', 'g') = (select k from nm where length(k) >= 4)
   order by (nullif(f.sec_crd, '') is not null and q.sec_crd = f.sec_crd) desc, q.priority limit 1 $$;
revoke all on function public._firm_queue_id(uuid) from public, anon, authenticated;

create or replace function public._firm_checks_done(p_firm uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from firm_check_rows where firm_id = p_firm and state <> 'nc' $$;
revoke all on function public._firm_checks_done(uuid) from public, anon, authenticated;

create or replace function public.bump_firm_check(p_slug text, p_anon uuid) returns json
language plpgsql security definer set search_path = public as $$
declare f firms; v text; qid text; q research_queue; front int;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and launch_page and published;
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  if _firm_checks_done(f.id) >= 10 then return json_build_object('status', 'complete'); end if;
  v := case when auth.uid() is not null then 'u:' || auth.uid() when p_anon is not null then 'a:' || p_anon end;
  if v is null then return json_build_object('status', 'no_visitor'); end if;
  if exists (select 1 from check_bumps where firm_id = f.id and visitor = v and at > now() - interval '10 minutes')
     or (select count(*) from check_bumps where visitor = v and at > now() - interval '1 hour') >= 20 then
    return json_build_object('status', 'rate_limited'); end if;
  insert into check_bumps (firm_id, visitor) values (f.id, v) on conflict (firm_id, visitor) do update set at = now();
  delete from check_bumps where at < now() - interval '1 day';
  qid := _firm_queue_id(f.id);
  if qid is null then return json_build_object('status', 'not_in_queue'); end if;
  select * into q from research_queue where registry_id = qid for update;
  if q.status <> 'queued' then return json_build_object('status', q.status); end if; -- never re-queue claimed/submitted/...
  select min(priority) into front from research_queue where status = 'queued' and registry_id <> qid;
  if front is null or q.priority < front then return json_build_object('status', 'queued', 'front', true); end if;
  update research_queue set priority = front - 1, bumped_at = now(), updated_at = now() where registry_id = qid;
  return json_build_object('status', 'queued', 'front', true, 'bumped', true);
end $$;

-- Poll: the 10 check states (n, state) + queue state. No results beyond the state the summary already shows.
create or replace function public.firm_check_status(p_slug text) returns json
language plpgsql stable security definer set search_path = public as $$
declare f firms; q research_queue; qid text;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and launch_page and published;
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  qid := _firm_queue_id(f.id);
  if qid is not null then select * into q from research_queue where registry_id = qid; end if;
  return json_build_object('status', 'ok', 'done', _firm_checks_done(f.id), 'total', 10,
    'complete', _firm_checks_done(f.id) >= 10, 'queue', q.status, 'started_at', q.claimed_at,
    'checks', (select json_agg(json_build_object('n', n, 'state', state, 'count', count_label) order by n) from firm_check_rows where firm_id = f.id));
end $$;

create or replace function public.notify_when_checked(p_slug text, p_email text, p_anon uuid) returns json
language plpgsql security definer set search_path = public as $$
declare f firms; em text;
begin
  select * into f from firms where slug = p_slug and deleted_at is null and launch_page and published;
  if f.id is null then return json_build_object('status', 'not_found'); end if;
  em := lower(trim(coalesce((select email from auth.users where id = auth.uid()), p_email, '')));
  if em !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(em) > 200 then return json_build_object('status', 'bad_email'); end if;
  if auth.uid() is null and p_anon is null then return json_build_object('status', 'no_visitor'); end if;
  if exists (select 1 from check_requests where firm_id = f.id and lower(email) = em and notified_at is null) then
    return json_build_object('status', 'ok'); end if;
  if (select count(*) from check_requests where created_at > now() - interval '1 hour'
       and (user_id = auth.uid() or (auth.uid() is null and anon_id = p_anon))) >= 10 then
    return json_build_object('status', 'rate_limited'); end if;
  insert into check_requests (query, email, anon_id, user_id, firm_id, status)
    values (f.name, em, p_anon, auth.uid(), f.id, 'running');
  return json_build_object('status', 'ok');
end $$;

-- Notify worker: a request is ready only when its firm is published AND all 10 checks are done.
create or replace function public.ready_check_requests() returns table(id bigint, email text, query text, slug text, name text)
language sql stable security definer set search_path = public as $$
  select r.id, r.email, r.query, f.slug, f.name
  from check_requests r
  join lateral (
    select fm.* from firms fm
    where fm.published and fm.deleted_at is null and (
      fm.id = r.firm_id or lower(fm.name) = lower(trim(r.query)) or lower(fm.slug) = lower(trim(r.query))
      or lower(coalesce(fm.short_name,'')) = lower(trim(r.query))
      or exists (select 1 from vc_aliases a where a.firm_id = fm.id and lower(a.value) = lower(trim(r.query))))
    order by (fm.id = r.firm_id) desc limit 1) f on true
  where r.email is not null and r.notified_at is null and r.status in ('queued','running','done')
    and _firm_checks_done(f.id) >= 10
  order by r.created_at limit 50
$$;
revoke all on function public.ready_check_requests() from public, anon, authenticated;
grant execute on function public.ready_check_requests() to service_role;

revoke all on function public.bump_firm_check(text, uuid), public.firm_check_status(text), public.notify_when_checked(text, text, uuid) from public;
grant execute on function public.bump_firm_check(text, uuid), public.firm_check_status(text), public.notify_when_checked(text, text, uuid) to anon, authenticated, service_role;
