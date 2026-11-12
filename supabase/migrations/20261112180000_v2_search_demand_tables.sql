-- A. Search demand, additive only.
-- Tables and the two anon RPCs the investors page calls, plus v2_firms.demand_hidden.
-- No claim change, no cron, no go-live, no rewrite of firm_directory / firm_page.
-- Existing rows are not updated. CI has no v2 schema: this is a no-op there.
-- Undo: supabase/rollbacks/20261112180000_v2_search_demand_tables.sql
do $mig$
begin
  if to_regclass('public.v2_firms') is null or to_regclass('public.research_queue') is null then
    raise notice 'v2 search demand tables skipped';
    return;
  end if;

  execute $col$
alter table public.v2_firms
  add column if not exists demand_hidden boolean not null default false
$col$;
  execute $cmt$
comment on column public.v2_firms.demand_hidden is
  'True: a searched firm added with name and website only. Hidden from the directory, firm pages and sitemap until research is done. Existing firms stay false.'
$cmt$;

  execute $norm$
create or replace function public.v2_search_norm(p text)
returns text
language sql
immutable
set search_path to public
as $$
  select left(lower(regexp_replace(btrim(coalesce(p, '')), '\s+', ' ', 'g')), 100)
$$
$norm$;
  execute 'revoke all on function public.v2_search_norm(text) from public, anon, authenticated';

  execute $log$
create table if not exists public.v2_search_log (
  id bigint generated always as identity primary key,
  term text not null,
  term_norm text not null,
  page text not null,
  result_count integer not null default 0,
  top_firm_id bigint references public.v2_firms(firm_id) on delete set null,
  anon_key uuid not null,
  user_id uuid,
  created_at timestamptz not null default now(),
  constraint v2_search_log_term_ck check (length(term) between 2 and 100),
  constraint v2_search_log_count_ck check (result_count >= 0)
)
$log$;
  execute 'create index if not exists v2_search_log_anon_hour_idx on public.v2_search_log (anon_key, created_at desc)';
  execute 'create index if not exists v2_search_log_term_idx on public.v2_search_log (term_norm)';
  execute 'alter table public.v2_search_log enable row level security';
  execute 'revoke all on table public.v2_search_log from public, anon, authenticated';
  execute $lc$
comment on table public.v2_search_log is
  'Firm searches from the site. No IP and no email. Written only by v2_log_search.'
$lc$;

  execute $watch$
create table if not exists public.v2_firm_watch (
  id bigint generated always as identity primary key,
  term text not null,
  term_norm text not null,
  registry_id text references public.research_queue(registry_id) on delete set null,
  firm_id bigint references public.v2_firms(firm_id) on delete set null,
  email text,
  user_id uuid,
  anon_key uuid,
  created_at timestamptz not null default now(),
  notified_at timestamptz,
  notify_error text,
  constraint v2_firm_watch_term_ck check (length(term) between 2 and 100),
  constraint v2_firm_watch_who_ck check (
    (email is not null and user_id is null) or (email is null and user_id is not null)
  ),
  constraint v2_firm_watch_email_ck check (
    email is null
    or (email = lower(email)
        and length(email) <= 200
        and email ~* '^[a-z0-9._%+''-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$')
  )
)
$watch$;
  execute 'create unique index if not exists v2_firm_watch_user_key on public.v2_firm_watch (term_norm, user_id) where user_id is not null';
  execute 'create unique index if not exists v2_firm_watch_email_key on public.v2_firm_watch (term_norm, email) where email is not null';
  execute 'create index if not exists v2_firm_watch_open_idx on public.v2_firm_watch (term_norm) where firm_id is null';
  execute 'create index if not exists v2_firm_watch_pending_idx on public.v2_firm_watch (firm_id) where notified_at is null and notify_error is null';
  execute 'create index if not exists v2_firm_watch_anon_hour_idx on public.v2_firm_watch (anon_key, created_at desc) where anon_key is not null';
  execute 'alter table public.v2_firm_watch enable row level security';
  execute 'revoke all on table public.v2_firm_watch from public, anon, authenticated';
  execute $wc$
comment on table public.v2_firm_watch is
  'Ask to be emailed when a searched firm gets a page. One of email or user_id. Written only by v2_watch_firm and the demand job.'
$wc$;

  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant select, insert, update, delete on table public.v2_search_log, public.v2_firm_watch to service_role';
  end if;

  execute $fn$
create or replace function public.v2_log_search(
  p_term text,
  p_page text,
  p_result_count integer,
  p_top_slug text,
  p_anon uuid
) returns json
language plpgsql
security definer
set search_path to public
set statement_timeout to '3s'
set lock_timeout to '1s'
as $body$
declare
  raw text := left(regexp_replace(btrim(coalesce(p_term, '')), '\s+', ' ', 'g'), 100);
  norm text := public.v2_search_norm(p_term);
  pg text := left(regexp_replace(btrim(coalesce(p_page, '')), '\s+', ' ', 'g'), 80);
  fid bigint;
begin
  if length(coalesce(norm, '')) < 2 or p_anon is null then
    return json_build_object('ok', true, 'skipped', 'short');
  end if;
  if pg = '' then
    pg := '/';
  end if;
  if (
    select count(*) from public.v2_search_log
     where anon_key = p_anon and created_at > now() - interval '1 hour'
  ) >= 30 then
    return json_build_object('ok', true, 'skipped', 'rate');
  end if;
  if nullif(btrim(coalesce(p_top_slug, '')), '') is not null
     and to_regclass('public.v2_firm_live') is not null then
    select l.firm_id into fid
      from public.v2_firm_live l
      join public.v2_firms f on f.firm_id = l.firm_id
     where l.slug = lower(left(btrim(p_top_slug), 200))
       and not coalesce(f.archived, false)
       and not coalesce(f.demand_hidden, false)
     limit 1;
  end if;
  insert into public.v2_search_log (term, term_norm, page, result_count, top_firm_id, anon_key, user_id)
  values (
    raw,
    norm,
    pg,
    greatest(0, least(coalesce(p_result_count, 0), 100000)),
    fid,
    p_anon,
    auth.uid()
  );
  return json_build_object('ok', true);
end
$body$
$fn$;

  execute $watchfn$
create or replace function public.v2_watch_firm(
  p_term text,
  p_email text,
  p_anon uuid
) returns json
language plpgsql
security definer
set search_path to public
set statement_timeout to '3s'
set lock_timeout to '1s'
as $body$
declare
  raw text := left(regexp_replace(btrim(coalesce(p_term, '')), '\s+', ' ', 'g'), 100);
  norm text := public.v2_search_norm(p_term);
  uid uuid := auth.uid();
  em text := lower(btrim(coalesce(p_email, '')));
  n int;
begin
  if length(coalesce(norm, '')) < 2 or raw !~ '[[:alnum:]]' then
    return json_build_object('status', 'ignored');
  end if;
  if uid is null and p_anon is null then
    return json_build_object('status', 'ignored');
  end if;
  if uid is not null then
    em := null;
  elsif em !~* '^[a-z0-9._%+''-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$' or length(em) > 200 then
    return json_build_object('status', 'bad_email');
  end if;
  if (
    select count(*) from public.v2_firm_watch
     where created_at > now() - interval '1 hour'
       and ((uid is not null and user_id = uid) or (p_anon is not null and anon_key = p_anon))
  ) >= 10
  or (
    em is not null and (
      select count(*) from public.v2_firm_watch
       where email = em and created_at > now() - interval '1 day'
    ) >= 5
  ) then
    return json_build_object('status', 'rate_limited');
  end if;
  if uid is not null then
    insert into public.v2_firm_watch (term, term_norm, user_id, anon_key)
    values (raw, norm, uid, p_anon)
    on conflict (term_norm, user_id) where user_id is not null do nothing;
  else
    insert into public.v2_firm_watch (term, term_norm, email, anon_key)
    values (raw, norm, em, p_anon)
    on conflict (term_norm, email) where email is not null do nothing;
  end if;
  get diagnostics n = row_count;
  return json_build_object('status', 'ok', 'already', n = 0);
end
$body$
$watchfn$;

  execute 'revoke all on function public.v2_log_search(text, text, integer, text, uuid) from public';
  execute 'revoke all on function public.v2_watch_firm(text, text, uuid) from public';
  execute 'grant execute on function public.v2_log_search(text, text, integer, text, uuid) to anon, authenticated';
  execute 'grant execute on function public.v2_watch_firm(text, text, uuid) to anon, authenticated';
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.v2_log_search(text, text, integer, text, uuid) to service_role';
    execute 'grant execute on function public.v2_watch_firm(text, text, uuid) to service_role';
    execute 'grant execute on function public.v2_search_norm(text) to service_role';
  end if;
end
$mig$;
