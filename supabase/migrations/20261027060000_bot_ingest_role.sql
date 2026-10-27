-- research-ingest connects as bot_ingest, not with the service key.
-- This file does not set a password. Apply generates one and stores it as the edge secret
-- BOT_INGEST_DB_URL. Never commit the password, never print it, never write it into a log.
-- bot_writer stays NOLOGIN. It still has bots table grants. Do not give it a password.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'bot_ingest') then
    create role bot_ingest
      login
      nosuperuser
      nocreatedb
      nocreaterole
      noinherit
      noreplication
      nobypassrls
      connection limit 10
      password null;
  end if;
end $$;

alter role bot_ingest
  login
  nosuperuser
  nocreatedb
  nocreaterole
  noinherit
  noreplication
  nobypassrls
  connection limit 10;
alter role bot_ingest set statement_timeout = '30s';
alter role bot_ingest set lock_timeout = '5s';
alter role bot_ingest set idle_in_transaction_session_timeout = '15s';
alter role bot_ingest set search_path = public;
comment on role bot_ingest is
  'Login for research-ingest only. EXECUTE on the ingest RPCs. No table grants and no bypassrls. Password is set at apply time into the edge secret BOT_INGEST_DB_URL.';

comment on role bot_writer is
  'NOLOGIN. Still has table grants on bots. research-ingest uses bot_ingest. Do not set a password on bot_writer.';

-- The door reads these three through PostgREST today. The login role has no table grants,
-- so each read is a security-definer function with the same fields.

create or replace function public.ingest_trusted_domains()
returns jsonb
language plpgsql
volatile
security definer
set search_path = bots, public
as $$
begin
  perform bots.apply_limits();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'domain', domain, 'label', label, 'kind', kind, 'path_like', path_like
    ) order by domain)
    from trusted_source_domains
  ), '[]'::jsonb);
end $$;
comment on function public.ingest_trusted_domains() is
  'Allowlist for research-ingest sources and submit. Same columns the door used to select.';

create or replace function public.ingest_bot_feedback(p_bot text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = bots, public
as $$
begin
  perform bots.apply_limits();
  return coalesce((
    select jsonb_agg(jsonb_build_object('message', message, 'created_at', created_at) order by created_at desc)
    from (
      select message, created_at
        from bots.bot_feedback
       where active
         and (bot_id = '*' or (coalesce(p_bot, '') <> '' and starts_with(p_bot, bot_id)))
       order by created_at desc
       limit 20
    ) s
  ), '[]'::jsonb);
end $$;
comment on function public.ingest_bot_feedback(text) is
  'Feedback messages for one bot prefix, newest 20. bot_id * matches every bot.';

create or replace function public.ingest_needs_source(p_registry text, p_slug text, p_limit int)
returns jsonb
language plpgsql
volatile
security definer
set search_path = bots, public
as $$
declare n int := greatest(1, least(coalesce(p_limit, 100), 500));
begin
  perform bots.apply_limits();
  return coalesce((
    select jsonb_agg(to_jsonb(s) order by s.received_at desc)
    from (
      select submission_id, registry_id, slug, firm_name, record_id, field_path,
             checklist_item, value, received_at
        from facts_needing_source
       where (p_registry is null or registry_id = p_registry)
         and (p_slug is null or slug = p_slug)
       order by received_at desc
       limit n
    ) s
  ), '[]'::jsonb);
end $$;
comment on function public.ingest_needs_source(text, text, int) is
  'needs_source queue for research-ingest. Same columns as the view, no table grant required.';

revoke all on function public.ingest_trusted_domains() from public, anon, authenticated;
revoke all on function public.ingest_bot_feedback(text) from public, anon, authenticated;
revoke all on function public.ingest_needs_source(text, text, int) from public, anon, authenticated;

-- Schema usage is required to call a function. It is not a table grant.
revoke all on schema public from bot_ingest;
grant usage on schema public to bot_ingest;
revoke all on schema bots from bot_ingest;
revoke create on schema public from public;

revoke all on all tables in schema public from bot_ingest;
revoke all on all tables in schema bots from bot_ingest;
revoke all on all sequences in schema public from bot_ingest;
revoke all on all sequences in schema bots from bot_ingest;

do $$
declare r record;
  allow text[] := array[
    'ingest_auth', 'research_status', 'research_claim', 'ondemand_job_info', 'research_submit',
    'research_store_lps', 'research_enrich', 'firm_requests_list', 'fact_add_source',
    'research_fail', 'research_skip', 'research_gaps_list', 'research_claim_gaps',
    'ingest_trusted_domains', 'ingest_bot_feedback', 'ingest_needs_source'];
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = any(allow)
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
    execute format('grant execute on function %s to bot_ingest', r.sig);
    if exists (select 1 from pg_roles where rolname = 'service_role') then
      execute format('grant execute on function %s to service_role', r.sig);
    end if;
  end loop;

  -- PostgreSQL grants EXECUTE to PUBLIC by default. That would let this login call every
  -- function. Copy the current PUBLIC grant onto the roles that already have it, then
  -- revoke PUBLIC so bot_ingest keeps only the list above.
  for r in
    select p.oid, p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname not in ('pg_catalog', 'information_schema')
       and n.nspname not like 'pg_%'
       and has_function_privilege('bot_ingest', p.oid, 'execute')
       and not (n.nspname = 'public' and p.proname = any(allow))
  loop
    if exists (select 1 from pg_roles where rolname = 'anon')
       and has_function_privilege('anon', r.oid, 'execute') then
      execute format('grant execute on function %s to anon', r.sig);
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated')
       and has_function_privilege('authenticated', r.oid, 'execute') then
      execute format('grant execute on function %s to authenticated', r.sig);
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role')
       and has_function_privilege('service_role', r.oid, 'execute') then
      execute format('grant execute on function %s to service_role', r.sig);
    end if;
    execute format('revoke all on function %s from public', r.sig);
  end loop;

  if exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname not in ('pg_catalog', 'information_schema')
       and n.nspname not like 'pg_%'
       and has_function_privilege('bot_ingest', p.oid, 'execute')
       and not (n.nspname = 'public' and p.proname = any(allow))
  ) then
    raise exception 'bot_ingest can execute %', (
      select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text)
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname not in ('pg_catalog', 'information_schema')
         and n.nspname not like 'pg_%'
         and has_function_privilege('bot_ingest', p.oid, 'execute')
         and not (n.nspname = 'public' and p.proname = any(allow))
    );
  end if;

  if exists (
    select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname in ('public', 'bots')
       and (
         (c.relkind in ('r', 'v', 'm', 'p') and (
           has_table_privilege('bot_ingest', c.oid, 'SELECT')
           or has_table_privilege('bot_ingest', c.oid, 'INSERT')
           or has_table_privilege('bot_ingest', c.oid, 'UPDATE')
           or has_table_privilege('bot_ingest', c.oid, 'DELETE')))
         or (c.relkind = 'S' and (
           has_sequence_privilege('bot_ingest', c.oid, 'USAGE')
           or has_sequence_privilege('bot_ingest', c.oid, 'SELECT')
           or has_sequence_privilege('bot_ingest', c.oid, 'UPDATE')))
       )
  ) then
    raise exception 'bot_ingest has a table or sequence grant';
  end if;

  if exists (
    select 1 from pg_auth_members m
      join pg_roles granted on granted.oid = m.roleid
     where granted.rolname = 'bot_ingest'
  ) then
    raise exception 'bot_ingest must not be granted to another role';
  end if;
end $$;

-- Future functions created by the migration role are not executable by PUBLIC,
-- so a later function does not become callable by bot_ingest by default.
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema bots revoke execute on functions from public;

notify pgrst, 'reload schema';
