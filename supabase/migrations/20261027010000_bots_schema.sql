-- Bots schema (step 2). Move bot holding tables out of public. Do not copy rows.
-- ALTER TABLE SET SCHEMA keeps the data, indexes, identity sequences, foreign keys, and triggers.
-- research_queue stays in public: firm_check_status and firm_page read it, and the queue-page
-- trigger still creates the unchecked firm page. fact_sources, research_requests, and backup
-- tables stay in public.
-- This file does not delete search_log rows and does not change ingest key rows.

create schema if not exists bots;
comment on schema bots is 'Bot holding area. Bots write only here. Firm records change through the Enricher, a publish batch, the queue-page trigger, or a firm-request link.';
revoke all on schema bots from public;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'bot_writer') then
    create role bot_writer noinherit nologin connection limit 10;
  end if;
end $$;
alter role bot_writer noinherit nologin connection limit 10;
alter role bot_writer set statement_timeout = '30s';
alter role bot_writer set lock_timeout = '5s';
comment on role bot_writer is 'Limited bot role. NOLOGIN: the edge function keeps the service key. Timeouts on the role apply at login only, so every bot RPC also calls bots.apply_limits().';

create or replace function bots.apply_limits() returns void
language plpgsql
as $$
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);
end $$;
revoke all on function bots.apply_limits() from public;
comment on function bots.apply_limits() is 'SET LOCAL statement_timeout 30s and lock_timeout 5s for the current transaction. Role GUCs do not apply through PostgREST SET ROLE.';

-- Views that mention the tables block SET SCHEMA. Save them, drop them, move, recreate.
-- search_log_current lands in bots. The read views the site and the edge use stay in public.
set search_path to public;

create temp table _bots_view_deps on commit drop as
with recursive deps as (
  select c.oid as obj, 0 as depth
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and c.relname in (
       'research_submissions', 'research_enrichments', 'research_gaps', 'search_log',
       'enrichment_rows', 'ingest_keys', 'ingest_rate', 'ingest_settings', 'bot_feedback',
       'fact_source_additions', 'firm_lps', 'firm_lp_summary')
  union
  select rw.ev_class, d.depth + 1
    from deps d
    join pg_depend pd on pd.refobjid = d.obj and pd.classid = 'pg_rewrite'::regclass
    join pg_rewrite rw on rw.oid = pd.objid
   where rw.ev_class <> d.obj and d.depth < 8
)
select obj, max(depth) as depth from deps group by obj;

create temp table _bots_views on commit drop as
select c.oid, d.depth, n.nspname, c.relname, pg_get_viewdef(c.oid, true) as def, c.reloptions
  from _bots_view_deps d
  join pg_class c on c.oid = d.obj and c.relkind = 'v'
  join pg_namespace n on n.oid = c.relnamespace;

do $$
declare r record;
begin
  for r in select nspname, relname from _bots_views order by depth desc, relname loop
    execute format('drop view %I.%I', r.nspname, r.relname);
  end loop;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'research_submissions', 'research_enrichments', 'research_gaps', 'search_log',
    'enrichment_rows', 'ingest_keys', 'ingest_rate', 'ingest_settings', 'bot_feedback',
    'fact_source_additions', 'firm_lps', 'firm_lp_summary']
  loop
    if to_regclass('public.' || t) is null then
      raise exception 'expected public.% to move', t;
    end if;
    execute format('alter table public.%I set schema bots', t);
  end loop;
end $$;

set search_path to bots, public;

do $$
declare r record; dest text; def text; opts text;
begin
  for r in select * from _bots_views order by depth, relname loop
    dest := case when r.relname = 'search_log_current' then 'bots' else r.nspname end;
    def := regexp_replace(r.def,
      'public\.(research_submissions|research_enrichments|research_gaps|search_log|enrichment_rows|ingest_keys|ingest_rate|ingest_settings|bot_feedback|fact_source_additions|firm_lp_summary|firm_lps)\M',
      'bots.\1', 'g');
    def := regexp_replace(def, 'public\.search_log_current\M', 'bots.search_log_current', 'g');
    opts := case when r.reloptions is null then '' else ' with (' || array_to_string(r.reloptions, ', ') || ')' end;
    execute format('create view %I.%I%s as %s', dest, r.relname, opts, def);
    execute format('revoke all on %I.%I from public, anon, authenticated', dest, r.relname);
    if exists (select 1 from pg_roles where rolname = 'service_role') then
      execute format('grant select on %I.%I to service_role', dest, r.relname);
    end if;
  end loop;
end $$;

-- Point function bodies and search_path at the moved tables. Signatures follow the row type
-- (same OID). Unqualified names resolve because search_path is bots, public.
do $$
declare r record; def text; newdef text;
begin
  for r in
    select p.oid, n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
       and p.prosrc ~ '(research_submissions|research_enrichments|research_gaps|enrichment_rows|ingest_keys|ingest_rate|ingest_settings|bot_feedback|fact_source_additions|firm_lp_summary|firm_lps|search_log)'
  loop
    def := pg_get_functiondef(r.oid);
    newdef := regexp_replace(def,
      'public\.(research_submissions|research_enrichments|research_gaps|search_log|enrichment_rows|ingest_keys|ingest_rate|ingest_settings|bot_feedback|fact_source_additions|firm_lp_summary|firm_lps)\M',
      'bots.\1', 'g');
    newdef := regexp_replace(newdef, 'public\.search_log_current\M', 'bots.search_log_current', 'g');
    -- SQL bodies are checked at create time against the function's own search_path.
    newdef := regexp_replace(newdef, 'set search_path to ', 'set search_path to bots, ', 'i');
    if newdef is distinct from def then
      begin
        execute newdef;
      exception when others then
        raise exception 'rewriting % failed: %', r.sig, sqlerrm;
      end;
    end if;
    execute format('alter function %s set search_path = bots, public', r.sig);
  end loop;
end $$;

-- A researcher upload must not create or update a firm, stamp report_date, or copy a
-- search_log row with firm_id null. The payload keeps its own search_log. Existing null
-- firm_id rows are left for a later decision.
create or replace function public.ensure_firm_trg() returns trigger
language plpgsql security definer set search_path = bots, public as $$
begin
  -- Firm rows are created by the queue-page trigger, research_enrich, a publish batch, or firm_request_link.
  return null;
end $$;
revoke all on function public.ensure_firm_trg() from public, anon, authenticated;

create or replace function public.stamp_firm_report_trg() returns trigger
language plpgsql security definer set search_path = bots, public as $$
begin
  -- report_date is copied in _promote_submissions, when a batch publishes the firm.
  return null;
end $$;
revoke all on function public.stamp_firm_report_trg() from public, anon, authenticated;

create or replace function public.search_log_from_submission(p_id bigint) returns int
language plpgsql security definer set search_path = bots, public as $$
begin
  perform bots.apply_limits();
  return 0;
end $$;
revoke all on function public.search_log_from_submission(bigint) from public, anon, authenticated;

create or replace function public.search_log_from_enrichment(p_id bigint) returns int
language plpgsql security definer set search_path = bots, public as $$
declare e research_enrichments; n int;
begin
  perform bots.apply_limits();
  select * into e from research_enrichments where id = p_id;
  if e.id is null or not e.valid or e.firm_id is null then return 0; end if;
  delete from search_log where enrichment_id = p_id;
  insert into search_log(firm_id, registry_id, bot_id, section, source_site, query, searched_at, result, item_count, enrichment_id, name_only)
  select e.firm_id, e.registry_id, e.bot_id, lower(s->>'section'),
    coalesce(nullif(lower(s->>'site'), ''), _dom(s->>'url'), _dom(s->>'query')), coalesce(s->>'query', s->>'url'),
    coalesce(case when s->>'searched_at' ~ '^\d{4}-\d{2}-\d{2}' then (s->>'searched_at')::timestamptz end, e.received_at),
    case when s->>'result' in ('found', 'none', 'blocked', 'error') then s->>'result' else 'error' end,
    coalesce(case when s->>'item_count' ~ '^\d+$' then (s->>'item_count')::int end, 0), e.id,
    coalesce(s->>'name_only', '') in ('true', 't', '1')
      or lower(coalesce(s->>'note', '')) ~ '(^|[^a-z])name-only match'
  from jsonb_array_elements(case when jsonb_typeof(e.payload->'searches') = 'array' then e.payload->'searches' else '[]' end) s
  where lower(s->>'section') in ('overview', 'checks', 'legal', 'people', 'board_seats', 'funds', 'timeline', 'press', 'founders', 'lps');
  insert into search_log(firm_id, registry_id, bot_id, section, source_site, query, searched_at, result, item_count, enrichment_id)
  select e.firm_id, e.registry_id, e.bot_id, sec, _dom(url), min(url), e.received_at, 'found', count(*), e.id
  from (select case when section = 'people' and txt ~* '\m(board|director)' then 'board_seats' else section end sec, url
        from enrichment_items(e.payload) where ok and e.id < _rules_cutoff()
        union all
        select case when section = 'people' and f->>'kind' = 'board' then 'board_seats' else section end, url
        from checked_items(e.payload) where outcome = 'ok' and e.id >= _rules_cutoff()) x
  group by sec, _dom(url);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.search_log_from_enrichment(bigint) from public, anon, authenticated;

create or replace function public._promote_submissions(p_firm uuid) returns jsonb
language plpgsql security definer set search_path = bots, public as $fn$
declare b text := 'publish:' || coalesce(nullif(current_setting('app.publish_batch', true), ''), 'none');
  before jsonb; n int; c int := 0; sid bigint; qid text; d date;
begin
  qid := _firm_queue_id(p_firm);
  if qid is not null then
    perform ensure_firm_for_registry(qid, false);
  end if;
  insert into cleanup_backup(batch, firm_id, table_name, row_id, row_data)
  select b, p_firm, 'firm_check_rows', null, to_jsonb(r) from firm_check_rows r where r.firm_id = p_firm;
  select coalesce(jsonb_object_agg(firm_check_rows.n::text, firm_check_rows.state), '{}') into before from firm_check_rows where firm_id = p_firm;
  n := promote_bot_facts(p_firm);
  sid := apply_checks_for_firm(p_firm);
  select count(*) into c from firm_check_rows r where r.firm_id = p_firm and r.state is distinct from (before->>(r.n::text));
  select max(substring(s.payload->'firm'->>'generated_at' from '^\d{4}-\d{2}-\d{2}')::date) into d
    from research_submissions s
   where s.valid
     and s.registry_id in (qid, _registry_target(qid))
     and s.payload->'firm'->>'generated_at' ~ '^\d{4}-\d{2}-\d{2}';
  if d is not null then
    update firms set
      report_date = d,
      updated_at = now()
     where id = p_firm and deleted_at is null and (report_date is null or d > report_date);
  end if;
  return jsonb_build_object('facts', n, 'check_rows_changed', c, 'submission_id', sid);
end $fn$;
revoke all on function public._promote_submissions(uuid) from public, anon, authenticated;

-- Bot RPCs: local timeouts. SQL functions become plpgsql so they can call apply_limits.
do $$
declare r record; def text; nd text;
begin
  for r in
    select p.oid
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      join pg_language l on l.oid = p.prolang
     where n.nspname = 'public' and l.lanname = 'plpgsql'
       and p.proname in (
         'ingest_auth', 'research_claim', 'research_submit', 'research_store_lps', 'research_enrich',
         'fact_add_source', 'research_fail', 'research_skip', 'research_claim_gaps')
       and p.prosrc not like '%bots.apply_limits%'
  loop
    def := pg_get_functiondef(r.oid);
    nd := regexp_replace(def, '\mbegin\M', E'begin\n  perform bots.apply_limits();', 'i');
    if nd = def then
      raise exception 'could not inject bots.apply_limits into %', r.oid::regprocedure;
    end if;
    execute nd;
  end loop;
end $$;

do $$
declare r record; src text; body text;
begin
  for r in
    select p.proname, p.prosrc, p.proretset,
           pg_get_function_arguments(p.oid) as args,
           pg_get_function_result(p.oid) as result
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      join pg_language l on l.oid = p.prolang
     where n.nspname = 'public' and l.lanname = 'sql'
       and p.proname in ('research_status', 'research_gaps_list', 'ondemand_job_info', 'firm_requests_list')
  loop
    src := regexp_replace(btrim(r.prosrc), ';\s*$', '');
    if r.proretset then
      body := format(E'begin\n  perform bots.apply_limits();\n  return query %s;\nend', src);
    else
      body := format(E'begin\n  perform bots.apply_limits();\n  return (%s);\nend', src);
    end if;
    -- set_config is volatile. These four were SQL; the wrapper stays volatile so the timeout is set.
    execute format(
      'create or replace function public.%I(%s) returns %s language plpgsql volatile security definer set search_path = bots, public as $fn$ %s $fn$',
      r.proname, r.args, r.result, body);
  end loop;
end $$;

do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in (
         'ingest_auth', 'research_status', 'research_claim', 'ondemand_job_info', 'research_submit',
         'research_store_lps', 'research_enrich', 'firm_requests_list', 'fact_add_source',
         'research_fail', 'research_skip', 'research_gaps_list', 'research_claim_gaps')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
    execute format('grant execute on function %s to bot_writer', r.sig);
    if exists (select 1 from pg_roles where rolname = 'service_role') then
      execute format('grant execute on function %s to service_role', r.sig);
    end if;
  end loop;
end $$;

grant usage on schema bots to bot_writer;
grant select, insert, update, delete on all tables in schema bots to bot_writer;
grant usage, select on all sequences in schema bots to bot_writer;
do $$
declare t text;
begin
  foreach t in array array[
    'research_submissions', 'research_enrichments', 'research_gaps', 'search_log',
    'enrichment_rows', 'ingest_keys', 'ingest_rate', 'ingest_settings', 'bot_feedback',
    'fact_source_additions', 'firm_lps', 'firm_lp_summary']
  loop
    execute format('alter table bots.%I enable row level security', t);
    execute format('drop policy if exists bot_writer_all on bots.%I', t);
    execute format('create policy bot_writer_all on bots.%I for all to bot_writer using (true) with check (true)', t);
  end loop;
end $$;
revoke all on all tables in schema public from bot_writer;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant usage on schema bots to service_role;
    grant select, insert, update, delete on all tables in schema bots to service_role;
    grant usage, select on all sequences in schema bots to service_role;
  end if;
end $$;

-- Nightly retention. Does not touch rows with firm_id null (the existing unlinked log).
-- No new index: building one on the live log would lock the table. A nightly scan is acceptable.
create or replace function bots.purge_old_search_log() returns integer
language plpgsql security definer set search_path = bots, public as $$
declare n int;
begin
  delete from bots.search_log
   where firm_id is not null
     and coalesce(searched_at, created_at) < now() - interval '30 days';
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function bots.purge_old_search_log() from public;
comment on function bots.purge_old_search_log() is 'Delete bots.search_log rows older than 30 days that are tied to a firm. Rows with firm_id null are kept.';

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if not exists (select 1 from cron.job where jobname = 'bots-search-log-retention') then
      perform cron.schedule('bots-search-log-retention', '30 8 * * *', 'select bots.purge_old_search_log()');
    end if;
  end if;
end $$;

do $$
begin
  if to_regclass('public.research_submissions') is not null then
    raise exception 'research_submissions is still in public';
  end if;
  if to_regclass('bots.research_submissions') is null or to_regclass('bots.search_log') is null then
    raise exception 'bot tables did not move';
  end if;
  if to_regclass('public.research_queue') is null then
    raise exception 'research_queue must stay in public';
  end if;
  if to_regclass('public.facts_needing_source') is null or to_regclass('bots.search_log_current') is null then
    raise exception 'compatibility views were not recreated';
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'research_submit' and p.prosrc like '%bots.apply_limits%') then
    raise exception 'research_submit is missing bots.apply_limits';
  end if;
end $$;

notify pgrst, 'reload schema';
set search_path to public;
