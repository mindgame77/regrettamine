-- Auto-publish switch for the v2 research door.
-- Default is off: new rows stay hidden until the Checker, and empty firm fields stay held.
-- A firm is on when v2_auto_publish.enabled is true, or its firm_id is in firm_ids.
-- On means Accepted rows and Held firm/website values go live as soon as the door accepts them.
-- The checker queue stays open. A Checker reject takes an auto-published row back down.
-- Rejected door items never go live. Turning the switch off does not hide rows already up.
--
-- Turn on for Paradigm only, then publish what is already waiting:
--   select public.v2_auto_publish_set(false, array[186]::bigint[]);
--   select public.v2_auto_publish_backfill(186);
-- Turn on for every firm:
--   select public.v2_auto_publish_set(true, '{}'::bigint[]);
--   select public.v2_auto_publish_backfill(null);
-- Turn the switch off (rows already up stay up):
--   select public.v2_auto_publish_set(false, '{}'::bigint[]);
-- Hide what the switch put up for one firm, then bring it back:
--   select public.v2_auto_publish_pull(186, null, null, null);
--   select public.v2_auto_publish_restore(186, null, null, null);
-- The same pull/restore takes a bot_key_id and/or a received_at window.
-- p_from is inclusive, p_to is exclusive. Pass at least one of firm, bot, or time.
-- bot_key_id is v2_bot_keys.bot_key_id. Do not pass a key hash.
--
-- A shared startup, sector, or person stays up when another firm still shows it.
-- Only the pulled firm's own deals and rows go down.
-- Undo: supabase/rollbacks/20261110120000_v2_auto_publish.sql
-- Pull down first if you want those rows hidden, then run the rollback.
-- The v2 schema is not created here. CI has no v2 tables, so this is a no-op there.
-- Not applied to production by this change.

do $mig$
begin
  if to_regclass('public.v2_firms') is null
     or to_regclass('public.v2_checker_queue') is null
     or to_regclass('public.v2_research_submissions') is null
     or to_regclass('public.v2_bot_keys') is null
     or to_regclass('public.v2_deals') is null
     or to_regclass('public.v2_startups') is null
     or to_regclass('public.v2_change_log') is null
     or to_regclass('bots.ingest_keys') is null
     or to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is null
     or to_regprocedure('public.v2_checker_action(uuid,text,jsonb,boolean)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;

  execute $helpers$
-- Tables and functions for the auto-publish switch.
-- The door and the Checker call the internal functions. Alex calls the four admin functions.

create table if not exists public.v2_auto_publish (
  id boolean primary key default true check (id),
  enabled boolean not null default false,
  firm_ids bigint[] not null default '{}'
);

insert into public.v2_auto_publish (id, enabled, firm_ids)
values (true, false, '{}')
on conflict (id) do nothing;

create table if not exists public.v2_auto_published (
  queue_id bigint primary key references public.v2_checker_queue (queue_id),
  submission_id bigint not null,
  firm_id bigint,
  bot_key_id bigint,
  table_name text not null,
  row_id bigint,
  kind text not null,
  applied_at timestamptz not null default now(),
  prior jsonb,
  live boolean not null default true,
  pulled_at timestamptz
);

create index if not exists v2_auto_published_firm_idx on public.v2_auto_published (firm_id);
create index if not exists v2_auto_published_bot_idx on public.v2_auto_published (bot_key_id);

alter table public.v2_auto_publish enable row level security;
alter table public.v2_auto_published enable row level security;
revoke all on table public.v2_auto_publish from public;
revoke all on table public.v2_auto_published from public;

comment on table public.v2_auto_publish is
  'Auto-publish switch. enabled is the global on/off. firm_ids is the allowlist. A firm is on when enabled is true or its id is in firm_ids. Default is off.';
comment on table public.v2_auto_published is
  'Rows the switch put live. Queue status stays open. prior saves the old firm-field values or the old visibility flags. pulled_at is set by a pull and cleared by a restore.';

create or replace function public.v2_auto_publish_on(p_firm_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce((
    select ap.enabled or (p_firm_id is not null and p_firm_id = any(ap.firm_ids))
    from public.v2_auto_publish ap
    where ap.id
  ), false);
$fn$;

create or replace function public.v2_auto_publish_pk(p_table text)
returns text
language sql
immutable
as $fn$
  select case p_table
    when 'v2_investor_principles' then 'id'
    when 'v2_firm_stages' then 'id'
    when 'v2_firm_industries' then 'id'
    when 'firm_fund_announcements' then 'id'
    when 'v2_firm_check_sizes' then 'id'
    else 'row_id'
  end;
$fn$;

create or replace function public.v2_auto_publish_allowed(p_table text)
returns boolean
language sql
immutable
as $fn$
  select p_table = any(array[
    'v2_deals','v2_startups','v2_startup_sectors','v2_people','v2_person_firm_roles',
    'v2_firm_industries','v2_firm_stages','v2_investor_principles','firm_fund_announcements',
    'v2_funds','v2_social_accounts','v2_legal_items','v2_firm_contacts','v2_interviews',
    'v2_sec_registration','v2_firm_check_sizes','v2_fund_assets','v2_firm_aum',
    'v2_reviews','v2_board_seats','v2_sec_fact_pills','v2_firm_registry_ids',
    'v2_firm_former_names','v2_firm_types_firms'
  ]);
$fn$;

create or replace function public.v2_auto_publish_log(p_firm_id bigint, p_result text, p_detail jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
  insert into public.v2_change_log (actor, firm_id, box, table_name, new_value, result)
  values ('v2_auto_publish', p_firm_id, 'P15', 'v2_auto_publish', p_detail, p_result);
end
$fn$;

create or replace function public.v2_auto_publish_shared(p_table text, p_row_id bigint, p_firm_id bigint)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_startup bigint;
  v_person bigint;
begin
  if p_table = 'v2_startups' then
    select s.startup_id into v_startup from public.v2_startups s where s.row_id = p_row_id;
    if v_startup is null then
      v_startup := p_row_id;
    end if;
    return exists (
      select 1 from public.v2_deals d
      where d.startup_id = v_startup
        and d.firm_id is distinct from p_firm_id
        and d.is_current and not d.archived and coalesce(d.shown, true));
  elsif p_table = 'v2_startup_sectors' then
    select ss.startup_id into v_startup from public.v2_startup_sectors ss where ss.row_id = p_row_id;
    return exists (
      select 1 from public.v2_deals d
      where d.startup_id = v_startup
        and d.firm_id is distinct from p_firm_id
        and d.is_current and not d.archived and coalesce(d.shown, true));
  elsif p_table = 'v2_people' then
    select pe.person_id into v_person from public.v2_people pe where pe.row_id = p_row_id;
    if v_person is null then
      v_person := p_row_id;
    end if;
    return exists (
      select 1 from public.v2_person_firm_roles r
      where r.person_id = v_person
        and r.firm_id is distinct from p_firm_id
        and r.is_current and not r.archived);
  end if;
  return false;
end
$fn$;

create or replace function public.v2_auto_publish_write_firm(p_firm_id bigint, p_patch jsonb)
returns int
language plpgsql
security definer
set search_path = public
as $fn$
declare
  allowed text[] := array[
    'legal_name','legal_name_source','founded_year','founded_year_source',
    'thesis_text','thesis_source','hq_street','hq_suite','hq_city','hq_state',
    'hq_postal','hq_country','hq_source','website_url','short_name'];
  keys text;
  n int := 0;
begin
  if p_patch is null or p_patch = '{}'::jsonb then
    return 0;
  end if;
  select string_agg(format('%I', k), ',' order by k) into keys
  from jsonb_object_keys(p_patch) k
  where k = any(allowed);
  if keys is null then
    return 0;
  end if;
  perform 1 from public.v2_firms where firm_id = p_firm_id for update;
  execute format(
    'update public.v2_firms t set (%s) = (select %s from jsonb_populate_record(null::public.v2_firms, $1)) where firm_id = $2',
    keys, keys
  ) using p_patch, p_firm_id;
  get diagnostics n = row_count;
  return n;
end
$fn$;

create or replace function public.v2_auto_publish_field_patch(p_cur jsonb, p_prior jsonb, p_use text)
returns jsonb
language plpgsql
immutable
as $fn$
declare
  allowed text[] := array[
    'legal_name','legal_name_source','founded_year','founded_year_source',
    'thesis_text','thesis_source','hq_street','hq_suite','hq_city','hq_state',
    'hq_postal','hq_country','hq_source','website_url','website_source','short_name'];
  k text;
  patch jsonb := '{}'::jsonb;
  conflicts int := 0;
  wrote int := 0;
begin
  -- p_use 'applied' builds the values to put back. p_use 'before' builds the values to restore on pull/reject.
  -- A key is writable only when the live value still equals the value this switch wrote.
  for k in select jsonb_object_keys(p_prior->'applied') loop
    if not (k = any(allowed)) then
      continue;
    end if;
    if p_cur->k is not distinct from (p_prior->'applied')->k then
      patch := patch || jsonb_build_object(k, p_prior->p_use->k);
      wrote := wrote + 1;
    else
      conflicts := conflicts + 1;
    end if;
  end loop;
  return jsonb_build_object('patch', patch, 'wrote', wrote, 'conflicts', conflicts);
end
$fn$;

create or replace function public.v2_auto_publish_show_row(p_table text, p_row_id bigint)
returns int
language plpgsql
security definer
set search_path = public
as $fn$
declare
  n int := 0;
  pk text;
begin
  if not public.v2_auto_publish_allowed(p_table) then
    return 0;
  end if;
  pk := public.v2_auto_publish_pk(p_table);
  if p_table = 'v2_deals' then
    update public.v2_deals
       set is_current = true,
           shown = (deal_date is not null or round_amount is not null)
     where row_id = p_row_id and not archived;
    get diagnostics n = row_count;
    return n;
  end if;
  execute format(
    'update public.%I set is_current = true where %I = $1 and not archived',
    p_table, pk
  ) using p_row_id;
  get diagnostics n = row_count;
  return n;
end
$fn$;

create or replace function public.v2_auto_publish_hide_row(p_table text, p_row_id bigint, p_archive boolean, p_reason text)
returns int
language plpgsql
security definer
set search_path = public
as $fn$
declare
  n int := 0;
  pk text;
begin
  if not public.v2_auto_publish_allowed(p_table) then
    return 0;
  end if;
  pk := public.v2_auto_publish_pk(p_table);
  if p_archive then
    if p_table = 'v2_deals' then
      update public.v2_deals
         set archived = true, is_current = false, shown = false, archive_reason = left(p_reason, 300)
       where row_id = p_row_id and not archived;
      get diagnostics n = row_count;
      return n;
    end if;
    execute format(
      'update public.%I set archived = true, is_current = false, archive_reason = left($1, 300) where %I = $2 and not archived',
      p_table, pk
    ) using p_reason, p_row_id;
    get diagnostics n = row_count;
    return n;
  end if;
  if p_table = 'v2_deals' then
    update public.v2_deals
       set is_current = false, shown = false
     where row_id = p_row_id and not archived;
    get diagnostics n = row_count;
    return n;
  end if;
  execute format(
    'update public.%I set is_current = false where %I = $1 and not archived',
    p_table, pk
  ) using p_row_id;
  get diagnostics n = row_count;
  return n;
end
$fn$;

create or replace function public.v2_auto_publish_apply_queue(p_queue_id bigint)
returns text
language plpgsql
security definer
set search_path = public
set statement_timeout to '30s'
set lock_timeout to '5s'
as $fn$
declare
  q public.v2_checker_queue;
  sub public.v2_research_submissions;
  cur jsonb;
  arch boolean;
  iscur boolean;
  shown boolean;
  pk text;
  prior jsonb;
  n int;
begin
  select * into q from public.v2_checker_queue where queue_id = p_queue_id for update;
  if not found then
    return 'skipped: queue missing';
  end if;
  if q.archived or q.status is distinct from 'open' then
    return 'skipped: not open';
  end if;
  if not public.v2_auto_publish_on(q.firm_id) then
    return 'off';
  end if;
  if exists (
    select 1 from public.v2_auto_published ap
    where ap.queue_id = q.queue_id and ap.pulled_at is not null
  ) then
    return 'skipped: pulled';
  end if;
  if exists (
    select 1 from public.v2_auto_published ap
    where ap.queue_id = q.queue_id and ap.live
  ) then
    return 'already';
  end if;
  select * into sub from public.v2_research_submissions where submission_id = q.submission_id;
  if not found or sub.status like 'Rejected:%' then
    return 'skipped: rejected';
  end if;
  if q.kind = 'new-firm' then
    return 'skipped: new firm stays with the Checker';
  end if;

  if q.kind = 'changed-key-fact' and q.table_name = 'v2_firms' then
    select to_jsonb(f) into cur from public.v2_firms f where f.firm_id = q.firm_id for update;
    if cur is null then
      return 'skipped: firm missing';
    end if;
    prior := jsonb_build_object('before', (
      select coalesce(jsonb_object_agg(k, cur->k), '{}'::jsonb)
      from jsonb_object_keys(q.new_value) k
      where k = any(array[
        'legal_name','legal_name_source','founded_year','founded_year_source',
        'thesis_text','thesis_source','hq_street','hq_suite','hq_city','hq_state',
        'hq_postal','hq_country','hq_source','website_url','short_name'])
    ), 'applied', (
      select coalesce(jsonb_object_agg(k, q.new_value->k), '{}'::jsonb)
      from jsonb_object_keys(q.new_value) k
      where k = any(array[
        'legal_name','legal_name_source','founded_year','founded_year_source',
        'thesis_text','thesis_source','hq_street','hq_suite','hq_city','hq_state',
        'hq_postal','hq_country','hq_source','website_url','short_name'])
    ));
    if prior->'applied' = '{}'::jsonb then
      return 'skipped: no firm field';
    end if;
    n := public.v2_auto_publish_write_firm(q.firm_id, prior->'applied');
    if n = 0 then
      return 'skipped: firm not updated';
    end if;
  elsif q.kind = 'changed-key-fact' and q.table_name = 'v2_startups' then
    select to_jsonb(s) into cur from public.v2_startups s
     where s.startup_id = q.row_id and not s.archived for update;
    if cur is null then
      return 'skipped: startup missing';
    end if;
    if coalesce(cur->>'website_url','') <> '' and cur->>'website_url' is distinct from (q.new_value->>'website_url') then
      return 'skipped: website already set';
    end if;
    update public.v2_startups s
       set website_url = q.new_value->>'website_url',
           website_source = q.new_value->'website_source'
     where s.startup_id = q.row_id and not s.archived;
    prior := jsonb_build_object(
      'before', jsonb_build_object('website_url', cur->'website_url', 'website_source', cur->'website_source'),
      'applied', jsonb_build_object('website_url', q.new_value->'website_url', 'website_source', q.new_value->'website_source'));
  elsif q.kind in ('accepted-item','name-only') then
    if not public.v2_auto_publish_allowed(q.table_name) then
      return 'skipped: table not allowed';
    end if;
    pk := public.v2_auto_publish_pk(q.table_name);
    execute format(
      'select archived, is_current from public.%I where %I = $1',
      q.table_name, pk
    ) into arch, iscur using q.row_id;
    if arch is null then
      return 'skipped: row missing';
    end if;
    if arch then
      return 'skipped: archived';
    end if;
    shown := null;
    if q.table_name = 'v2_deals' then
      select d.shown into shown from public.v2_deals d where d.row_id = q.row_id;
    end if;
    n := public.v2_auto_publish_show_row(q.table_name, q.row_id);
    if n = 0 then
      return 'skipped: row not updated';
    end if;
    prior := jsonb_build_object('is_current', iscur, 'shown', shown, 'archived', arch);
  else
    return 'skipped: kind';
  end if;

  insert into public.v2_auto_published (
    queue_id, submission_id, firm_id, bot_key_id, table_name, row_id, kind, prior, live, pulled_at
  ) values (
    q.queue_id, q.submission_id, q.firm_id, sub.bot_key_id, q.table_name, q.row_id, q.kind, prior, true, null
  )
  on conflict (queue_id) do update
    set live = true,
        pulled_at = null,
        prior = excluded.prior,
        applied_at = now(),
        bot_key_id = excluded.bot_key_id
  where public.v2_auto_published.pulled_at is null;
  return 'published';
end
$fn$;

create or replace function public.v2_auto_publish_apply_submission(p_submission_id bigint)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
declare
  r record;
  msg text := 'no-queue';
begin
  for r in
    select q.queue_id
    from public.v2_checker_queue q
    where q.submission_id = p_submission_id and q.status = 'open' and not q.archived
    order by q.queue_id
  loop
    msg := public.v2_auto_publish_apply_queue(r.queue_id);
  end loop;
  return msg;
end
$fn$;

create or replace function public.v2_auto_publish_take_down(p_queue_id bigint, p_mode text, p_reason text)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
declare
  ap public.v2_auto_published;
  cur jsonb;
  built jsonb;
  n int;
  outcome text;
begin
  if p_mode not in ('pull','reject') then
    return 'skipped: mode';
  end if;
  select * into ap from public.v2_auto_published where queue_id = p_queue_id for update;
  if not found then
    return 'missing';
  end if;
  if p_mode = 'pull' and ap.pulled_at is not null then
    return 'already';
  end if;
  if ap.prior ? 'applied' and ap.table_name = 'v2_firms' then
    select to_jsonb(f) into cur from public.v2_firms f where f.firm_id = ap.firm_id for update;
    built := public.v2_auto_publish_field_patch(cur, ap.prior, 'before');
    if coalesce((built->>'wrote')::int, 0) > 0 then
      perform public.v2_auto_publish_write_firm(ap.firm_id, built->'patch');
      outcome := 'reverted';
    else
      outcome := 'conflict';
    end if;
  elsif ap.prior ? 'applied' and ap.table_name = 'v2_startups' then
    select to_jsonb(s) into cur from public.v2_startups s where s.startup_id = ap.row_id for update;
    built := public.v2_auto_publish_field_patch(cur, ap.prior, 'before');
    if coalesce((built->>'wrote')::int, 0) > 0 then
      update public.v2_startups s
         set website_url = case when built->'patch' ? 'website_url' then built#>>'{patch,website_url}' else s.website_url end,
             website_source = case when built->'patch' ? 'website_source' then built#>'{patch,website_source}' else s.website_source end
       where s.startup_id = ap.row_id;
      outcome := 'reverted';
    else
      outcome := 'conflict';
    end if;
  elsif public.v2_auto_publish_shared(ap.table_name, ap.row_id, ap.firm_id) then
    outcome := 'left_shared';
  elsif p_mode = 'reject' then
    n := public.v2_auto_publish_hide_row(ap.table_name, ap.row_id, true, coalesce(p_reason, 'Checker rejected'));
    outcome := case when n > 0 then 'archived' else 'skipped' end;
  else
    n := public.v2_auto_publish_hide_row(ap.table_name, ap.row_id, false, null);
    outcome := case when n > 0 then 'hidden' else 'skipped' end;
  end if;
  update public.v2_auto_published
     set live = false,
         pulled_at = case when p_mode = 'pull' then now() else pulled_at end
   where queue_id = p_queue_id;
  return outcome;
end
$fn$;

create or replace function public.v2_auto_publish_checker_reject(p_queue_id bigint, p_reason text)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
declare
  outcome text;
begin
  if not exists (select 1 from public.v2_auto_published where queue_id = p_queue_id) then
    return null;
  end if;
  outcome := public.v2_auto_publish_take_down(p_queue_id, 'reject', p_reason);
  return case outcome
    when 'reverted' then 'Rejected: auto-published value reverted'
    when 'archived' then 'Rejected: auto-published row taken down'
    when 'left_shared' then 'Rejected: shared row kept for other firms'
    when 'conflict' then 'Rejected: auto-published value was edited later and left as-is'
    else 'Rejected: auto-published item closed'
  end;
end
$fn$;

create or replace function public.v2_auto_publish_restore_one(p_queue_id bigint)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
declare
  ap public.v2_auto_published;
  q public.v2_checker_queue;
  sub public.v2_research_submissions;
  cur jsonb;
  arch boolean;
  built jsonb;
  n int;
  pk text;
begin
  select * into ap from public.v2_auto_published where queue_id = p_queue_id for update;
  if not found or ap.pulled_at is null then
    return 'skipped: not pulled';
  end if;
  select * into q from public.v2_checker_queue where queue_id = p_queue_id;
  select * into sub from public.v2_research_submissions where submission_id = ap.submission_id;
  if q.status = 'failed' or q.archived or coalesce(sub.status,'') like 'Rejected:%' then
    return 'skipped: checker closed';
  end if;
  if ap.prior ? 'applied' and ap.table_name = 'v2_firms' then
    select to_jsonb(f) into cur from public.v2_firms f where f.firm_id = ap.firm_id for update;
    built := public.v2_auto_publish_field_patch(
      cur,
      jsonb_build_object('applied', ap.prior->'before', 'before', ap.prior->'applied'),
      'before');
    -- field_patch treats "applied" as the value that must still be on the row.
    -- After a pull, that value is `before`. The value to write back is the original `applied`,
    -- which field_patch returns when p_use is before and we swap the two sides above.
    if coalesce((built->>'wrote')::int, 0) = 0 then
      return 'conflict';
    end if;
    perform public.v2_auto_publish_write_firm(ap.firm_id, built->'patch');
  elsif ap.prior ? 'applied' and ap.table_name = 'v2_startups' then
    select to_jsonb(s) into cur from public.v2_startups s where s.startup_id = ap.row_id for update;
    built := public.v2_auto_publish_field_patch(
      cur,
      jsonb_build_object('applied', ap.prior->'before', 'before', ap.prior->'applied'),
      'before');
    if coalesce((built->>'wrote')::int, 0) = 0 then
      return 'conflict';
    end if;
    update public.v2_startups s
       set website_url = case when built->'patch' ? 'website_url' then built#>>'{patch,website_url}' else s.website_url end,
           website_source = case when built->'patch' ? 'website_source' then built#>'{patch,website_source}' else s.website_source end
     where s.startup_id = ap.row_id;
  else
    if not public.v2_auto_publish_allowed(ap.table_name) then
      return 'skipped: table not allowed';
    end if;
    pk := public.v2_auto_publish_pk(ap.table_name);
    execute format('select archived from public.%I where %I = $1', ap.table_name, pk)
      into arch using ap.row_id;
    if arch is null then
      return 'skipped: row missing';
    end if;
    if arch then
      return 'skipped: archived';
    end if;
    n := public.v2_auto_publish_show_row(ap.table_name, ap.row_id);
    if n = 0 then
      return 'skipped: row not updated';
    end if;
  end if;
  update public.v2_auto_published
     set live = true, pulled_at = null
   where queue_id = p_queue_id;
  return 'restored';
end
$fn$;

create or replace function public.v2_auto_publish_set(p_enabled boolean, p_firm_ids bigint[] default '{}')
returns jsonb
language plpgsql
security definer
set search_path = public
set statement_timeout to '30s'
set lock_timeout to '5s'
as $fn$
declare
  ids bigint[] := coalesce(p_firm_ids, '{}'::bigint[]);
  unknown bigint[];
  out jsonb;
begin
  if p_enabled is null then
    raise exception 'v2_auto_publish: enabled is required';
  end if;
  select coalesce(array_agg(distinct f order by f), '{}') into ids from unnest(ids) f;
  select coalesce(array_agg(f order by f), '{}') into unknown
  from unnest(ids) f
  where not exists (select 1 from public.v2_firms where firm_id = f);
  if cardinality(unknown) > 0 then
    raise exception 'v2_auto_publish: unknown firm_id %', unknown;
  end if;
  insert into public.v2_auto_publish (id, enabled, firm_ids)
  values (true, p_enabled, ids)
  on conflict (id) do update
    set enabled = excluded.enabled,
        firm_ids = excluded.firm_ids;
  out := jsonb_build_object('ok', true, 'enabled', p_enabled, 'firm_ids', to_jsonb(ids));
  perform public.v2_auto_publish_log(null, 'Blocked: auto-publish switch set', out);
  return out;
end
$fn$;

create or replace function public.v2_auto_publish_backfill(p_firm_id bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = public
set statement_timeout to '60s'
set lock_timeout to '5s'
as $fn$
declare
  r record;
  msg text;
  published int := 0;
  already int := 0;
  skipped int := 0;
  errors int := 0;
  samples jsonb := '[]'::jsonb;
  out jsonb;
begin
  if p_firm_id is not null and not public.v2_auto_publish_on(p_firm_id) then
    return jsonb_build_object('ok', false, 'error', 'switch is off for this firm', 'firm_id', p_firm_id);
  end if;
  for r in
    select q.queue_id
    from public.v2_checker_queue q
    where q.status = 'open' and not q.archived
      and (p_firm_id is null or q.firm_id = p_firm_id)
      and public.v2_auto_publish_on(q.firm_id)
    order by q.queue_id
    for update of q
  loop
    begin
      msg := public.v2_auto_publish_apply_queue(r.queue_id);
    exception when others then
      msg := left('error: '||sqlerrm, 200);
    end;
    if msg = 'published' then
      published := published + 1;
    elsif msg = 'already' then
      already := already + 1;
    elsif msg like 'error:%' then
      errors := errors + 1;
      if jsonb_array_length(samples) < 20 then
        samples := samples || jsonb_build_array(jsonb_build_object('queue_id', r.queue_id, 'result', msg));
      end if;
    else
      skipped := skipped + 1;
      if msg is distinct from 'off' and jsonb_array_length(samples) < 20 then
        samples := samples || jsonb_build_array(jsonb_build_object('queue_id', r.queue_id, 'result', msg));
      end if;
    end if;
  end loop;
  out := jsonb_build_object(
    'ok', true, 'firm_id', p_firm_id, 'published', published, 'already', already,
    'skipped', skipped, 'errors', errors, 'samples', samples);
  perform public.v2_auto_publish_log(
    p_firm_id,
    case when published > 0 then 'Accepted' else 'Blocked: auto-publish backfill found nothing' end,
    out);
  return out;
end
$fn$;

create or replace function public.v2_auto_publish_scope(
  p_firm_id bigint, p_bot_key_id bigint, p_from timestamptz, p_to timestamptz)
returns table (queue_id bigint)
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  if p_firm_id is null and p_bot_key_id is null and p_from is null and p_to is null then
    raise exception 'v2_auto_publish: pass a firm_id, bot_key_id, or time window';
  end if;
  if p_from is not null and p_to is not null and p_from >= p_to then
    raise exception 'v2_auto_publish: from_time must be before to_time';
  end if;
  return query
  select ap.queue_id
  from public.v2_auto_published ap
  join public.v2_research_submissions s on s.submission_id = ap.submission_id
  where (p_firm_id is null or ap.firm_id = p_firm_id)
    and (p_bot_key_id is null or ap.bot_key_id = p_bot_key_id)
    and (p_from is null or s.received_at >= p_from)
    and (p_to is null or s.received_at < p_to)
  order by ap.queue_id;
end
$fn$;

create or replace function public.v2_auto_publish_pull(
  p_firm_id bigint default null,
  p_bot_key_id bigint default null,
  p_from timestamptz default null,
  p_to timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = public
set statement_timeout to '60s'
set lock_timeout to '5s'
as $fn$
declare
  qid bigint;
  msg text;
  matched int := 0;
  hidden int := 0;
  reverted int := 0;
  left_shared int := 0;
  conflicts int := 0;
  skipped int := 0;
  out jsonb;
begin
  for qid in
    select ap.queue_id
    from public.v2_auto_published ap
    where ap.queue_id in (
      select s.queue_id from public.v2_auto_publish_scope(p_firm_id, p_bot_key_id, p_from, p_to) s)
      and ap.table_name not in ('v2_startups','v2_startup_sectors','v2_people')
    order by ap.queue_id desc
    for update of ap
  loop
    matched := matched + 1;
    msg := public.v2_auto_publish_take_down(qid, 'pull', null);
    if msg = 'hidden' then hidden := hidden + 1;
    elsif msg = 'reverted' then reverted := reverted + 1;
    elsif msg = 'left_shared' then left_shared := left_shared + 1;
    elsif msg = 'conflict' then conflicts := conflicts + 1;
    else skipped := skipped + 1;
    end if;
  end loop;
  for qid in
    select ap.queue_id
    from public.v2_auto_published ap
    where ap.queue_id in (
      select s.queue_id from public.v2_auto_publish_scope(p_firm_id, p_bot_key_id, p_from, p_to) s)
      and ap.table_name in ('v2_startups','v2_startup_sectors','v2_people')
    order by ap.queue_id desc
    for update of ap
  loop
    matched := matched + 1;
    msg := public.v2_auto_publish_take_down(qid, 'pull', null);
    if msg = 'hidden' then hidden := hidden + 1;
    elsif msg = 'reverted' then reverted := reverted + 1;
    elsif msg = 'left_shared' then left_shared := left_shared + 1;
    elsif msg = 'conflict' then conflicts := conflicts + 1;
    else skipped := skipped + 1;
    end if;
  end loop;
  out := jsonb_build_object(
    'ok', true, 'firm_id', p_firm_id, 'bot_key_id', p_bot_key_id,
    'matched', matched, 'hidden', hidden, 'reverted', reverted,
    'left_shared', left_shared, 'conflicts', conflicts, 'skipped', skipped);
  perform public.v2_auto_publish_log(p_firm_id, 'Blocked: auto-publish pulled', out);
  return out;
end
$fn$;

create or replace function public.v2_auto_publish_restore(
  p_firm_id bigint default null,
  p_bot_key_id bigint default null,
  p_from timestamptz default null,
  p_to timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = public
set statement_timeout to '60s'
set lock_timeout to '5s'
as $fn$
declare
  qid bigint;
  msg text;
  matched int := 0;
  restored int := 0;
  conflicts int := 0;
  skipped int := 0;
  out jsonb;
begin
  for qid in
    select s.queue_id
    from public.v2_auto_publish_scope(p_firm_id, p_bot_key_id, p_from, p_to) s
    join public.v2_auto_published ap on ap.queue_id = s.queue_id
    where ap.table_name in ('v2_startups','v2_people','v2_startup_sectors')
       or ap.kind = 'changed-key-fact'
    order by s.queue_id
    for update of ap
  loop
    matched := matched + 1;
    msg := public.v2_auto_publish_restore_one(qid);
    if msg = 'restored' then restored := restored + 1;
    elsif msg = 'conflict' then conflicts := conflicts + 1;
    else skipped := skipped + 1;
    end if;
  end loop;
  for qid in
    select s.queue_id
    from public.v2_auto_publish_scope(p_firm_id, p_bot_key_id, p_from, p_to) s
    join public.v2_auto_published ap on ap.queue_id = s.queue_id
    where ap.table_name not in ('v2_startups','v2_people','v2_startup_sectors')
      and ap.kind is distinct from 'changed-key-fact'
    order by s.queue_id
    for update of ap
  loop
    matched := matched + 1;
    msg := public.v2_auto_publish_restore_one(qid);
    if msg = 'restored' then restored := restored + 1;
    elsif msg = 'conflict' then conflicts := conflicts + 1;
    else skipped := skipped + 1;
    end if;
  end loop;
  out := jsonb_build_object(
    'ok', true, 'firm_id', p_firm_id, 'bot_key_id', p_bot_key_id,
    'matched', matched, 'restored', restored, 'conflicts', conflicts, 'skipped', skipped);
  perform public.v2_auto_publish_log(
    p_firm_id,
    case when restored > 0 then 'Accepted' else 'Blocked: auto-publish restore found nothing' end,
    out);
  return out;
end
$fn$;

$helpers$;

  execute $submitfn$
CREATE OR REPLACE FUNCTION public.v2_research_submit(p_key_id uuid, p_items jsonb, p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
DECLARE
  ik bots.ingest_keys; bk public.v2_bot_keys; bot text; batch bigint;
  it jsonb; idx int := -1; firmkey text; firms text[] := '{}'; refused jsonb := '[]'; results jsonb := '[]';
  tbl text; box text; fact jsonb; p jsonb; k text; v jsonb; reason text; sid bigint; fid bigint; res jsonb;
  sec_id smallint; o_site text; empty_fill boolean; ft_id smallint;
  pkcol text; newid bigint; cols text; refs jsonb := '{}'; q_kind text; o jsonb; n jsonb; upd jsonb; diff boolean;
  rej_today int; firms_hour int; frz text; acc int := 0; rejn int := 0; held int := 0;
  src_tables text[] := ARRAY['v2_funds','v2_fund_assets','v2_startups','v2_startup_sectors','v2_deals','v2_people',
    'v2_person_firm_roles','v2_board_seats','v2_interviews','v2_legal_items','v2_sec_registration','v2_sec_fact_pills','v2_social_accounts',
    'v2_reviews','v2_firm_aum','v2_firm_contacts','v2_firm_registry_ids',
    'v2_investor_principles','v2_firm_stages','v2_firm_industries','v2_firm_types_firms','firm_fund_announcements','v2_firm_check_sizes','v2_firm_former_names'];
  firm_fields jsonb := '{"legal_name":"legal_name_source","founded_year":"founded_year_source","thesis_text":"thesis_source","hq_street":"hq_source","hq_suite":"hq_source","hq_city":"hq_source","hq_state":"hq_source","hq_postal":"hq_source","hq_country":"hq_source","website_url":null,"short_name":null}';
  blocked text[] := ARRAY['row_id','submission_id','archived','archive_reason','created_at','is_current','source_url_norm','archived_url_norm','link_dead','website_source'];
  src_keys text[] := ARRAY['source_url','source_level','source_date','source_date_precision','source_date_is_found_date','source_type','source_owner','archived_url','nothing_found'];
  v_st_web text; v_st_raw text; v_st_host text; v_st_id bigint; v_st_name text; v_st_note text; v_st_match boolean := false; v_cname text;
  v_site_reason text := 'website_url required: find this startup''s website or skip the startup and its deal';
  -- Hosted-platform domains are not a startup's own website. One list. The host or any subdomain of it is rejected.
  v_platform_hosts text[] := ARRAY['linktr.ee','medium.com','github.com','notion.site','wixsite.com','carrd.co','substack.com','linkedin.com','facebook.com','x.com','twitter.com','instagram.com'];
BEGIN
  SELECT * INTO ik FROM bots.ingest_keys WHERE id = p_key_id AND active;
  IF NOT FOUND OR ik.bot_id IS NULL THEN RETURN jsonb_build_object('ok',false,'error','this key is not linked to a bot'); END IF;
  bot := ik.bot_id;
  INSERT INTO public.v2_bot_keys (bot_name, key_hash) VALUES (bot, ik.key_hash)
    ON CONFLICT (bot_name) DO UPDATE SET key_hash = EXCLUDED.key_hash RETURNING * INTO bk;
  IF bk.frozen THEN
    RETURN jsonb_build_object('ok',false,'error',format('Key frozen: %s, %s', coalesce(bk.freeze_reason,'no reason'), to_char(bk.freeze_date AT TIME ZONE 'America/Los_Angeles','YYYY-MM-DD HH24:MI "PT"')));
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN RETURN jsonb_build_object('ok',false,'error','items must be a non-empty array'); END IF;
  IF jsonb_array_length(p_items) > 500 THEN RETURN jsonb_build_object('ok',false,'error','max 500 items per batch'); END IF;
  batch := nextval('public.v2_batch_seq');

  BEGIN  -- whole batch; rolled back at the end when p_dry_run
  FOR it IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    idx := idx + 1; reason := NULL; sid := NULL; newid := NULL; q_kind := NULL; res := NULL;
    v_st_match := false; v_st_id := NULL; v_st_name := NULL; v_st_raw := NULL; v_st_host := NULL; v_cname := NULL;
    IF jsonb_typeof(it) <> 'object' THEN
      results := results || jsonb_build_object('index',idx,'status','Rejected: item must be an object'); CONTINUE; END IF;
    firmkey := coalesce(it->>'firm_id', it->>'firm_ref');
    IF firmkey IS NULL THEN
      results := results || jsonb_build_object('index',idx,'status','Rejected: firm_id (existing firm) or firm_ref (new firm) required'); CONTINUE; END IF;
    IF NOT firmkey = ANY(firms) THEN
      IF cardinality(firms) >= 10 THEN
        refused := refused || jsonb_build_object('index',idx,'firm',firmkey,'status','Refused: batch over 10 firms; firms 11+ are refused, send them in the next batch (I1.5)'); CONTINUE; END IF;
      firms := firms || firmkey;
    END IF;
    tbl := it->>'table'; box := it->>'box'; fact := coalesce(it->'fact','{}');
    fid := CASE WHEN (it->>'firm_id') ~ '^\d+$' THEN (it->>'firm_id')::bigint END;
    IF it->>'firm_id' IS NOT NULL AND fid IS NULL THEN reason := 'firm_id must be a number';
    ELSIF box IS NULL OR box !~ '^[A-Z]{1,3}[0-9]{1,3}[a-z]?$' THEN reason := 'box required (e.g. F12)';
    ELSIF tbl IS NULL OR NOT (tbl = ANY(src_tables) OR tbl = 'v2_firms') THEN reason := format('unknown table "%s" (P9)', coalesce(tbl,''));
    ELSIF jsonb_typeof(fact) <> 'object' THEN reason := 'fact must be an object';
    ELSIF fid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.v2_firms WHERE firm_id = fid) THEN reason := format('firm_id %s not found', fid);
    END IF;
    -- source checks (R2, P1, P2, S1-S4)
    IF reason IS NULL THEN
      fact := fact || jsonb_build_object('source_owner', coalesce(fact->>'source_owner', bot));
      IF coalesce(fact->>'source_url','') = '' THEN reason := 'no source link (source_url)';
      ELSIF (fact->>'source_url') ~* '(google\.[a-z.]+/search|bing\.com/search|duckduckgo\.com/\?|grok\.com|x\.com/i/grok|chatgpt\.com|perplexity\.ai/search)' THEN reason := 'source_url is a search/chat page; cite the page itself';
      ELSIF (fact->>'source_url') !~* '^(https?://)?(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(/[^\s]*)?$' THEN reason := 'source_url is not a valid link';
      ELSIF coalesce(fact->>'source_level','') !~ '^[1-4]$' THEN reason := 'no source level (source_level must be 1, 2, 3 or 4)';
      ELSIF coalesce(fact->>'source_date','') !~ '^\d{4}-\d{2}-\d{2}$' THEN reason := 'no source date (source_date YYYY-MM-DD)';
      ELSIF coalesce(fact->>'source_type','') = '' THEN reason := 'no source type (source_type)';
      END IF;
      IF reason IS NULL THEN
        BEGIN IF (fact->>'source_date')::date > current_date THEN reason := 'source_date is in the future'; END IF;
        EXCEPTION WHEN others THEN reason := 'source_date is not a real date'; END;
      END IF;
    END IF;
    IF reason IS NULL AND tbl = 'v2_sec_fact_pills' AND lower(btrim(coalesce(fact->>'fact_label',''))) IN ('staff','investment staff') THEN
      reason := 'Staff and Investment staff are not accepted';
    END IF;
    -- G5.2 (Alex 2026-11-04 12:40 PM PT): a review's reviewer_role / reviewer_company needs a valid reviewer_role_source_url
    IF reason IS NULL AND tbl = 'v2_reviews' AND (coalesce(btrim(fact->>'reviewer_role'),'') <> '' OR coalesce(btrim(fact->>'reviewer_company'),'') <> '') THEN
      IF coalesce(btrim(fact->>'reviewer_role_source_url'),'') = '' THEN reason := 'reviewer_role/reviewer_company sent without reviewer_role_source_url (G5.2)';
      ELSIF (fact->>'reviewer_role_source_url') ~* '(google\.[a-z.]+/search|bing\.com/search|duckduckgo\.com/\?|grok\.com|x\.com/i/grok|chatgpt\.com|perplexity\.ai/search)' THEN reason := 'reviewer_role_source_url is a search/chat page; cite the page itself (G5.2)';
      ELSIF (fact->>'reviewer_role_source_url') !~* '^https?://(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(/[^\s]*)?$' THEN reason := 'reviewer_role_source_url is not a valid link (G5.2)';
      END IF;
    END IF;
    -- G5.2.1 (Alex 2026-11-04 12:54 PM PT): a review_author that replaces the name on an existing review of the same quote/source
    -- (e.g. a username -> a real name) needs reviewer_name_source_url; any reviewer_name_source_url given must be a valid link
    IF reason IS NULL AND tbl = 'v2_reviews' THEN
      IF coalesce(btrim(fact->>'reviewer_name_source_url'),'') <> '' THEN
        IF (fact->>'reviewer_name_source_url') ~* '(google\.[a-z.]+/search|bing\.com/search|duckduckgo\.com/\?|grok\.com|x\.com/i/grok|chatgpt\.com|perplexity\.ai/search)' THEN reason := 'reviewer_name_source_url is a search/chat page; cite the page itself (G5.2.1)';
        ELSIF (fact->>'reviewer_name_source_url') !~* '^https?://(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(/[^\s]*)?$' THEN reason := 'reviewer_name_source_url is not a valid link (G5.2.1)';
        END IF;
      ELSIF coalesce(btrim(fact->>'review_author'),'') <> '' AND EXISTS (
        SELECT 1 FROM public.v2_reviews r WHERE r.firm_id = fid AND NOT r.archived
          AND coalesce(btrim(r.review_author),'') <> '' AND lower(btrim(r.review_author)) <> lower(btrim(fact->>'review_author'))
          AND (lower(rtrim(btrim(r.source_url),'/')) = lower(rtrim(btrim(fact->>'source_url'),'/')) OR btrim(r.quote) = btrim(fact->>'quote'))) THEN
        reason := 'review_author replaces the name on an existing review; send reviewer_name_source_url (the page that states the name) (G5.2.1)';
      END IF;
    END IF;
    -- 015: sector rows may name the ST5 word ("sector") instead of sector_id; max 2 per startup
    IF reason IS NULL AND tbl = 'v2_startup_sectors' AND fact ? 'sector' THEN
      SELECT sector_id INTO sec_id FROM public.v2_sector WHERE lower(name) = lower(trim(fact->>'sector'));
      IF sec_id IS NULL THEN reason := format('unknown sector "%s" (use one of the 18 ST5 sectors)', fact->>'sector');
      ELSIF fact ? 'sector_id' AND (fact->>'sector_id') IS DISTINCT FROM sec_id::text THEN reason := 'sector and sector_id disagree';
      ELSE fact := (fact - 'sector') || jsonb_build_object('sector_id', sec_id); END IF;
    END IF
;
    IF reason IS NULL AND tbl = 'v2_firm_types_firms' AND fact ? 'firm_type' THEN
      SELECT t.firm_type_id INTO ft_id FROM public.v2_firm_type t WHERE lower(t.name) = lower(btrim(fact->>'firm_type')) ORDER BY t.firm_type_id LIMIT 1;
      IF ft_id IS NULL THEN reason := format('unknown firm type "%s"', fact->>'firm_type');
      ELSIF fact ? 'firm_type_id' AND (fact->>'firm_type_id') IS DISTINCT FROM ft_id::text THEN reason := 'firm_type and firm_type_id disagree';
      ELSE fact := (fact - 'firm_type') || jsonb_build_object('firm_type_id', ft_id); END IF;
    END IF;
    IF reason IS NULL AND tbl = 'v2_investor_principles' THEN
      IF char_length(btrim(coalesce(fact->>'quote',''))) = 0 THEN reason := 'quote required (exact excerpt, 150 characters or less)';
      ELSIF char_length(btrim(fact->>'quote')) > 150 THEN reason := 'quote is over 150 characters (exact excerpt, 150 characters or less)';
      ELSIF NOT (fact ? 'display_order') AND fid IS NOT NULL THEN
        fact := fact || jsonb_build_object('display_order', coalesce((SELECT max(pr.display_order) FROM public.v2_investor_principles pr WHERE pr.firm_id = fid), 0) + 1);
      END IF;
      IF reason IS NULL AND nullif(btrim(fact->>'published_at'),'') IS NULL THEN
        fact := fact - 'published_at';
      END IF;
    END IF;
    IF reason IS NULL AND tbl = 'v2_firm_stages' AND NOT (fact ? 'read_on') AND coalesce(fact->>'source_date','') <> '' THEN
      fact := fact || jsonb_build_object('read_on', fact->>'source_date');
    END IF;
    IF reason IS NULL AND tbl = 'v2_firm_industries' AND NOT (fact ? 'date_read') AND coalesce(fact->>'source_date','') <> '' THEN
      fact := fact || jsonb_build_object('date_read', fact->>'source_date');
    END IF;
    IF reason IS NULL AND tbl = 'v2_firm_check_sizes' THEN
      IF fact ? 'currency' AND upper(btrim(coalesce(fact->>'currency',''))) <> 'USD' THEN
        reason := 'check size currency must be USD';
      ELSIF fact ? 'currency' THEN
        fact := fact - 'currency';
      END IF;
      IF reason IS NULL AND NOT (fact ? 'read_on') AND coalesce(fact->>'source_date','') <> '' THEN
        fact := fact || jsonb_build_object('read_on', fact->>'source_date');
      END IF;
      IF reason IS NULL AND nullif(btrim(coalesce(fact->>'amount_text','')),'') IS NULL THEN
        reason := 'check size amount_text is required (source excerpt, not shown)';
      END IF;
      IF reason IS NULL AND fact ? 'min_usd' AND fact->'min_usd' <> 'null'::jsonb AND btrim(coalesce(fact->>'min_usd','')) !~ '^[1-9][0-9]*$' THEN
        reason := 'check size min_usd must be a positive whole number of US dollars';
      END IF;
      IF reason IS NULL AND fact ? 'max_usd' AND fact->'max_usd' <> 'null'::jsonb AND btrim(coalesce(fact->>'max_usd','')) !~ '^[1-9][0-9]*$' THEN
        reason := 'check size max_usd must be a positive whole number of US dollars';
      END IF;
      IF reason IS NULL AND nullif(btrim(coalesce(fact->>'min_usd','')),'') IS NULL AND nullif(btrim(coalesce(fact->>'max_usd','')),'') IS NULL THEN
        reason := 'check size needs min_usd or max_usd';
      END IF;
      IF reason IS NULL AND nullif(btrim(coalesce(fact->>'min_usd','')),'') IS NOT NULL AND nullif(btrim(coalesce(fact->>'max_usd','')),'') IS NOT NULL AND (btrim(fact->>'min_usd'))::numeric > (btrim(fact->>'max_usd'))::numeric THEN
        reason := 'check size min_usd is greater than max_usd';
      END IF;
    END IF;
    IF reason IS NULL AND tbl = 'firm_fund_announcements' THEN
      IF NOT (fact ? 'url') AND coalesce(fact->>'source_url','') <> '' THEN fact := fact || jsonb_build_object('url', fact->>'source_url'); END IF;
      IF NOT (fact ? 'retrieved_on') AND coalesce(fact->>'source_date','') <> '' THEN fact := fact || jsonb_build_object('retrieved_on', fact->>'source_date'); END IF;
    END IF;
    IF reason IS NULL THEN
      SELECT string_agg(key, ', ') INTO k FROM jsonb_object_keys(fact) key WHERE key = ANY(blocked) OR key LIKE '%\_norm';
      IF k IS NOT NULL THEN reason := 'field not allowed (set by the database): '||k; END IF;
    END IF;
    IF reason IS NULL AND tbl <> 'v2_firms' THEN
      SELECT string_agg(key, ', ') INTO k FROM jsonb_object_keys(fact) key
        WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema='public' AND c.table_name=tbl AND c.column_name=key);
      IF k IS NOT NULL THEN reason := 'unknown field: '||k; END IF;
    END IF;
    -- resolve @refs from earlier items of this batch
    p := '{}';
    IF reason IS NULL THEN
      FOR k, v IN SELECT * FROM jsonb_each(fact) LOOP
        IF jsonb_typeof(v) = 'string' AND left(v#>>'{}',1) = '@' THEN
          IF refs ? substr(v#>>'{}',2) THEN p := p || jsonb_build_object(k, refs->substr(v#>>'{}',2));
          ELSE reason := format('ref %s not found in this batch (the item that makes it was rejected, held, or comes later)', v#>>'{}'); EXIT; END IF;
        ELSE p := p || jsonb_build_object(k, v); END IF;
      END LOOP;
      IF tbl <> 'v2_firms' AND p ? 'firm_id' = false AND EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema='public' AND c.table_name=tbl AND c.column_name='firm_id') THEN
        p := p || jsonb_build_object('firm_id', fid); END IF;
    END IF;

    INSERT INTO public.v2_research_submissions (batch_id, firm_id, bot_key_id, target_box, payload)
      VALUES (batch, fid, bk.bot_key_id, coalesce(box,'?'), jsonb_build_object('target_table',tbl,'fact',coalesce(it->'fact','{}'::jsonb),'firm_ref',it->>'firm_ref','ref',it->>'ref','origin',it->>'note','source_owner',coalesce(fact->>'source_owner',bot),'item_index',idx))
      RETURNING submission_id INTO sid;

    IF reason IS NULL AND tbl = 'v2_firms' THEN
      IF fid IS NULL THEN  -- only the publish step creates a firm (F1.3.1)
        reason := NULL; q_kind := 'new-firm';
        INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, new_value) VALUES (sid, NULL, 'new-firm', tbl, p);
        UPDATE public.v2_research_submissions SET status = 'Held: new firm waits for the Checker (F1.3.1)' WHERE submission_id = sid;
        INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, submission_id, new_value, result) VALUES (bot, NULL, box, tbl, sid, p, 'Blocked: held, new firm waits for the Checker');
        held := held + 1;
        results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Held: new firm waits for the Checker (F1.3.1)','checker_queued','new-firm');
        CONTINUE;
      END IF;
      SELECT string_agg(key, ', ') INTO k FROM jsonb_object_keys(p) key WHERE NOT (key = ANY(src_keys) OR firm_fields ? key);
      IF k IS NOT NULL THEN reason := 'unknown firm field: '||k||' (allowed: '||(SELECT string_agg(x,', ') FROM jsonb_object_keys(firm_fields) x)||')'; END IF;
      IF reason IS NULL AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p) key WHERE firm_fields ? key) THEN reason := 'no firm field to set'; END IF;
      IF reason IS NULL THEN
        SELECT to_jsonb(f) INTO o FROM public.v2_firms f WHERE firm_id = fid;
        upd := '{}'; diff := false; empty_fill := false;
        FOR k, v IN SELECT * FROM jsonb_each(p) WHERE firm_fields ? key LOOP
          upd := upd || jsonb_build_object(k, v);
          IF firm_fields->>k IS NOT NULL THEN upd := upd || jsonb_build_object(firm_fields->>k, jsonb_build_object('url',p->>'source_url','level',(p->>'source_level')::int,'date',p->>'source_date')); END IF;
          IF o->k IS NOT NULL AND o->k <> 'null'::jsonb AND nullif(btrim(o->>k),'') IS NOT NULL AND (o->>k) IS DISTINCT FROM (v#>>'{}') THEN diff := true;
          ELSIF nullif(btrim(v#>>'{}'),'') IS NOT NULL AND (o->k IS NULL OR o->k = 'null'::jsonb OR nullif(btrim(o->>k),'') IS NULL) THEN empty_fill := true; END IF;
        END LOOP;
        IF diff THEN  -- changed key fact: never overwrite directly (P15)
          INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, old_value, new_value)
            VALUES (sid, fid, 'changed-key-fact', tbl, fid, (SELECT jsonb_object_agg(x, o->x) FROM jsonb_object_keys(upd) x), upd);
          UPDATE public.v2_research_submissions SET status = 'Held: changed key fact waits for the Checker (P15)' WHERE submission_id = sid;
          INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result) VALUES (bot, fid, box, tbl, fid, sid, o, upd, 'Blocked: held, changed key fact waits for the Checker');
          held := held + 1;
          results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Held: changed key fact waits for the Checker (P15)','checker_queued','changed-key-fact');
          PERFORM public.v2_auto_publish_apply_submission(sid);
          CONTINUE;
        END IF;
        IF empty_fill THEN
          INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, old_value, new_value)
            VALUES (sid, fid, 'changed-key-fact', tbl, fid, (SELECT jsonb_object_agg(x, o->x) FROM jsonb_object_keys(upd) x), upd);
          UPDATE public.v2_research_submissions SET status = 'Held: empty firm field waits for the Checker' WHERE submission_id = sid;
          INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
            VALUES (bot, fid, box, tbl, fid, sid, (SELECT jsonb_object_agg(x, o->x) FROM jsonb_object_keys(upd) x), upd, 'Blocked: held, empty firm field waits for the Checker');
          held := held + 1;
          results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Held: empty firm field waits for the Checker','checker_queued','changed-key-fact');
          PERFORM public.v2_auto_publish_apply_submission(sid);
          CONTINUE;
        END IF;
        BEGIN
          EXECUTE format('UPDATE public.v2_firms t SET (%s) = (SELECT %s FROM jsonb_populate_record(NULL::public.v2_firms, $1)), last_checked_date = current_date WHERE firm_id = $2 RETURNING to_jsonb(t)',
            (SELECT string_agg(format('%I',x),',') FROM jsonb_object_keys(upd) x), (SELECT string_agg(format('%I',x),',') FROM jsonb_object_keys(upd) x)) INTO n USING upd, fid;
          UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = sid;
          INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
            VALUES (bot, fid, box, tbl, fid, sid, (SELECT jsonb_object_agg(x, o->x) FROM jsonb_object_keys(upd) x), (SELECT jsonb_object_agg(x, n->x) FROM jsonb_object_keys(upd) x), 'Accepted');
          acc := acc + 1;
          results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,'row_id',fid);
          CONTINUE;
        EXCEPTION WHEN others THEN reason := left(SQLERRM, 300); END;
      END IF;
    END IF;

    -- 015: sector row for a startup: max 2 per startup (11. startup_sectors), startup must exist
    IF reason IS NULL AND tbl = 'v2_startup_sectors' THEN
      IF (p->>'startup_id') !~ '^\d+$' OR NOT EXISTS (SELECT 1 FROM public.v2_startups WHERE startup_id = (p->>'startup_id')::bigint AND NOT archived) THEN
        reason := format('startup_id %s not found', coalesce(p->>'startup_id',''));
      ELSIF EXISTS (SELECT 1 FROM public.v2_startup_sectors WHERE startup_id = (p->>'startup_id')::bigint AND sector_id = (p->>'sector_id')::smallint) THEN
        reason := 'sector already set for this startup';
      ELSIF (SELECT count(*) FROM public.v2_startup_sectors WHERE startup_id = (p->>'startup_id')::bigint AND NOT archived) >= 2 THEN
        reason := 'startup already has 2 sectors (max 2)';
      END IF;
    END IF;
    -- 015: website fill for an EXISTING startup (fact has startup_id): fills an empty website_url only; never a new startup, never overwrites
    IF reason IS NULL AND tbl = 'v2_startups' AND p ? 'startup_id' THEN
      SELECT string_agg(key, ', ') INTO k FROM jsonb_object_keys(p) key WHERE NOT (key = ANY(src_keys) OR key IN ('startup_id','website_url'));
      IF k IS NOT NULL THEN reason := 'existing startup: only website_url can be filled (not allowed: '||k||')';
      ELSIF coalesce(p->>'website_url','') = '' THEN reason := 'existing startup: website_url required';
      ELSIF (p->>'startup_id') !~ '^\d+$' THEN reason := 'startup_id must be a number';
      ELSE
        SELECT to_jsonb(s) INTO o FROM public.v2_startups s WHERE startup_id = (p->>'startup_id')::bigint AND NOT archived;
        IF o IS NULL THEN reason := format('startup_id %s not found', p->>'startup_id');
        ELSE
          o_site := nullif(o->>'website_url','');
          IF o_site IS NOT NULL THEN
            IF lower(regexp_replace(regexp_replace(o_site,'^(https?://)?(www\.)?',''),'/+$','')) = lower(regexp_replace(regexp_replace(p->>'website_url','^(https?://)?(www\.)?',''),'/+$','')) THEN
              UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = sid;
              INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
                VALUES (bot, fid, box, tbl, (o->>'startup_id')::bigint, sid, jsonb_build_object('website_url',o_site), jsonb_build_object('website_url',p->>'website_url'), 'Accepted');
              acc := acc + 1;
              results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,'row_id',(o->>'startup_id')::bigint,'note','website already set to the same site; nothing changed');
              CONTINUE;
            END IF;
            reason := 'startup already has a different website_url; never overwritten (P15)';
          ELSIF (p->>'source_level') = '4' THEN reason := 'website fill needs source_level 1-3';
          ELSE
            INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, old_value, new_value)
              VALUES (sid, fid, 'changed-key-fact', tbl, (o->>'startup_id')::bigint,
                jsonb_build_object('website_url', NULL),
                jsonb_build_object('website_url', p->>'website_url',
                  'website_source', jsonb_build_object('url',p->>'source_url','level',(p->>'source_level')::int,'date',p->>'source_date','type',p->>'source_type','owner',p->>'source_owner','submission_id',sid)));
            UPDATE public.v2_research_submissions SET status = 'Held: empty startup website waits for the Checker' WHERE submission_id = sid;
            INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
              VALUES (bot, fid, box, tbl, (o->>'startup_id')::bigint, sid, jsonb_build_object('website_url',NULL), jsonb_build_object('website_url',p->>'website_url'), 'Blocked: held, empty startup website waits for the Checker');
            held := held + 1;
            IF it->>'ref' IS NOT NULL THEN refs := refs || jsonb_build_object(it->>'ref', (o->>'startup_id')::bigint); END IF;
            results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Held: empty startup website waits for the Checker','table',tbl,'row_id',(o->>'startup_id')::bigint,'checker_queued','changed-key-fact');
            PERFORM public.v2_auto_publish_apply_submission(sid);
            CONTINUE;
          END IF;
        END IF;
      END IF;
    END IF;

    -- New startup (no startup_id): the website is the only identity. A matching name does not matter.
    -- v2_startups.domain is generated as lower(split_part(regexp_replace(regexp_replace(website_url, '^https?://', '', 'i'), '^www\.', '', 'i'), '/', 1)).
    -- The lookup uses that expression. A port, query, fragment, or trailing dot left on that host is stripped for the comparison only.
    IF reason IS NULL AND tbl = 'v2_startups' AND NOT (p ? 'startup_id') THEN
      v_st_web := btrim(coalesce(p->>'website_url', ''));
      IF v_st_web IS DISTINCT FROM coalesce(p->>'website_url', '') THEN
        p := p || jsonb_build_object('website_url', v_st_web);
      END IF;
      v_st_raw := lower(split_part(regexp_replace(regexp_replace(v_st_web, '^https?://', '', 'i'), '^www\.', '', 'i'), '/', 1));
      v_st_host := regexp_replace(regexp_replace(split_part(split_part(v_st_raw, '?', 1), '#', 1), ':[0-9]+$', ''), '\.+$', '');
      IF v_st_host = '' OR EXISTS (
        SELECT 1 FROM unnest(v_platform_hosts) AS h(host)
        WHERE v_st_host = h.host OR right(v_st_host, length(h.host) + 1) = '.' || h.host
      ) THEN
        reason := v_site_reason;
      ELSE
        SELECT s.startup_id, s.startup_name INTO v_st_id, v_st_name
        FROM public.v2_startups s
        WHERE NOT s.archived AND s.domain IS NOT NULL AND s.domain <> '' AND s.domain = v_st_raw
        ORDER BY s.startup_id
        LIMIT 1;
        IF v_st_id IS NULL THEN
          SELECT s.startup_id, s.startup_name INTO v_st_id, v_st_name
          FROM public.v2_startups s
          WHERE NOT s.archived AND s.domain IS NOT NULL AND s.domain <> ''
            AND regexp_replace(regexp_replace(split_part(split_part(s.domain, '?', 1), '#', 1), ':[0-9]+$', ''), '\.+$', '') = v_st_host
          ORDER BY s.startup_id
          LIMIT 1;
        END IF;
        IF v_st_id IS NOT NULL THEN v_st_match := true; END IF;
      END IF;
    END IF;

    IF reason IS NULL AND tbl = 'v2_deals' AND btrim(coalesce(p->>'deal_date','')) ~ '^\d{4}$' THEN
      -- bare year stored as January 1 with the existing precision. The page shows the year only.
      p := p || jsonb_build_object('deal_date', btrim(p->>'deal_date') || '-01-01', 'deal_date_precision', 'year');
    END IF;
    IF reason IS NULL AND NOT v_st_match THEN
      IF (p->>'source_level') = '4' THEN p := p || '{"archived":true,"archive_reason":"L4 kept archived (R2)"}'; END IF;
      p := p || jsonb_build_object('submission_id', sid);
      SELECT string_agg(format('%I', key), ',') INTO cols FROM jsonb_object_keys(p) key;
      BEGIN
        EXECUTE format('INSERT INTO public.%I AS t (%s) SELECT %s FROM jsonb_populate_record(NULL::public.%I, $1) RETURNING to_jsonb(t)', tbl, cols, cols, tbl) INTO res USING p;
      EXCEPTION
        WHEN unique_violation THEN
          GET STACKED DIAGNOSTICS v_cname = CONSTRAINT_NAME;
          IF tbl = 'v2_startups' AND NOT (p ? 'startup_id') AND (v_cname = 'v2_startups_domain_uq' OR position('v2_startups_domain_uq' in SQLERRM) > 0) THEN
            SELECT s.startup_id, s.startup_name INTO v_st_id, v_st_name
            FROM public.v2_startups s
            WHERE NOT s.archived AND s.domain IS NOT NULL AND s.domain <> '' AND s.domain = v_st_raw
            ORDER BY s.startup_id
            LIMIT 1;
            IF v_st_id IS NULL THEN
              reason := left(SQLERRM, 300);
            ELSE
              v_st_match := true;
            END IF;
          ELSE
            reason := left(SQLERRM, 300);
          END IF;
        WHEN others THEN reason := left(SQLERRM, 300);
      END;
    END IF;

    IF v_st_match THEN
      v_st_note := format('matched existing startup %s by website (submitted "%s", existing "%s")', v_st_id, coalesce(nullif(btrim(p->>'startup_name'), ''), '(none)'), coalesce(nullif(btrim(v_st_name), ''), '(none)'));
      UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = sid;
      INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
        VALUES (bot, fid, box, tbl, v_st_id, sid,
          jsonb_build_object('startup_id', v_st_id, 'startup_name', v_st_name),
          jsonb_build_object('startup_name', p->>'startup_name', 'website_url', p->>'website_url'),
          'Accepted');
      IF it->>'ref' IS NOT NULL THEN refs := refs || jsonb_build_object(it->>'ref', v_st_id); END IF;
      acc := acc + 1;
      results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,'row_id',v_st_id,'matched_startup_id',v_st_id,'note',v_st_note);
      CONTINUE;
    END IF;

    IF reason IS NOT NULL THEN
      UPDATE public.v2_research_submissions SET status = 'Rejected: '||reason WHERE submission_id = sid;
      INSERT INTO public.v2_rejected_rows (payload, target_table, error_message, source_owner, submission_id, status)
        VALUES (coalesce(it->'fact','{}'::jsonb) || jsonb_build_object('_item', it - 'fact'), coalesce(tbl,'?'), reason, left(coalesce(fact->>'source_owner',bot),200), sid, 'new');
      INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, submission_id, new_value, result)
        VALUES (bot, fid, coalesce(box,'?'), coalesce(tbl,'?'), sid, it, 'Rejected: '||reason);
      rejn := rejn + 1;
      results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Rejected: '||reason);
      CONTINUE;
    END IF;

    pkcol := CASE tbl WHEN 'v2_funds' THEN 'fund_id' WHEN 'v2_startups' THEN 'startup_id' WHEN 'v2_people' THEN 'person_id'
                      WHEN 'v2_deals' THEN 'deal_id' WHEN 'v2_legal_items' THEN 'legal_item_id' WHEN 'v2_investor_principles' THEN 'id' WHEN 'v2_firm_stages' THEN 'id' WHEN 'v2_firm_industries' THEN 'id' WHEN 'firm_fund_announcements' THEN 'id' WHEN 'v2_firm_check_sizes' THEN 'id' ELSE 'row_id' END;
    newid := (res->>pkcol)::bigint;
    -- 011: new rows stay hidden until the Checker passes them (v2_publish_queue_item sets is_current/shown)
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name=tbl AND column_name='is_current') THEN
      EXECUTE format('UPDATE public.%I SET is_current = false WHERE submission_id = $1', tbl) USING sid;
    END IF;
    IF tbl = 'v2_deals' THEN UPDATE public.v2_deals SET shown = false WHERE submission_id = sid; END IF;
    IF it->>'ref' IS NOT NULL THEN refs := refs || jsonb_build_object(it->>'ref', newid); END IF;
    UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = sid;
    INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
      VALUES (bot, fid, box, tbl, newid, sid, NULL, res, 'Accepted');
    -- name-only rows go to the Checker (glossary 30, C4.2)
    IF NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p) key WHERE NOT (key = ANY(src_keys) OR key IN ('firm_id','submission_id','archived','archive_reason') OR key LIKE '%\_name')) THEN
      q_kind := 'name-only';
      INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, new_value) VALUES (sid, fid, 'name-only', tbl, newid, res);
    ELSE  -- 011: every accepted item goes live only after the Checker passes it (Checker-first, R4.1; covers 010 LP rows too)
      q_kind := 'accepted-item';
      INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, new_value) VALUES (sid, fid, 'accepted-item', tbl, newid, res);
    END IF;
    -- Auto-publish, when on for this firm, shows the row now. The queue stays open. Off is a no-op.
    PERFORM public.v2_auto_publish_apply_submission(sid);
    acc := acc + 1;
    results := results || jsonb_strip_nulls(jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,'row_id',newid,'checker_queued',q_kind,
      'note',CASE WHEN (p->>'source_level')='4' THEN 'L4: kept archived (R2)' END));
  END LOOP;

  -- freeze rules (I2.7)
  SELECT coalesce(max(firm_rej), 0)::int INTO rej_today FROM (
    SELECT count(*) AS firm_rej FROM public.v2_research_submissions
    WHERE bot_key_id = bk.bot_key_id AND status LIKE 'Rejected:%'
      AND status IS DISTINCT FROM ('Rejected: ' || v_site_reason)
      AND received_at >= date_trunc('day', now() AT TIME ZONE 'America/Los_Angeles') AT TIME ZONE 'America/Los_Angeles'
    GROUP BY coalesce(firm_id::text, payload->>'firm_ref')
  ) one_firm;
  SELECT count(DISTINCT coalesce(firm_id::text, payload->>'firm_ref')) INTO firms_hour FROM public.v2_research_submissions
    WHERE bot_key_id = bk.bot_key_id AND received_at > now() - interval '1 hour';
  frz := CASE WHEN rej_today >= 100 THEN format('%s rejections today for one firm', rej_today) WHEN firms_hour > 100 THEN format('%s firms in the last hour', firms_hour) END;
  IF frz IS NOT NULL AND NOT p_dry_run THEN
    UPDATE public.v2_bot_keys SET frozen = true, freeze_date = now(), freeze_reason = frz,
      freeze_count_7d = CASE WHEN freeze_date > now() - interval '7 days' THEN coalesce(freeze_count_7d,0) + 1 ELSE 1 END
      WHERE bot_key_id = bk.bot_key_id;
    INSERT INTO public.v2_change_log (actor, box, table_name, row_id, new_value, result)
      VALUES ('v2_research_submit', 'I2', 'v2_bot_keys', bk.bot_key_id, jsonb_build_object('bot',bot,'frozen',true,'reason',frz), 'Blocked: Key frozen: '||frz);
  END IF;

  IF p_dry_run THEN RAISE EXCEPTION 'v2_dry_run_rollback'; END IF;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'v2_dry_run_rollback' THEN RAISE; END IF;
  END;

  RETURN jsonb_strip_nulls(jsonb_build_object('ok', true, 'bot_id', bot, 'dry_run', p_dry_run, 'batch_id', CASE WHEN NOT p_dry_run THEN batch END,
    'accepted', acc, 'rejected', rejn, 'held', held, 'refused', jsonb_array_length(refused), 'firms', cardinality(firms),
    'results', results, 'refused_items', CASE WHEN jsonb_array_length(refused) > 0 THEN refused END,
    'key_frozen', CASE WHEN frz IS NOT NULL AND NOT p_dry_run THEN format('Key frozen: %s, %s', frz, to_char(now() AT TIME ZONE 'America/Los_Angeles','YYYY-MM-DD HH24:MI "PT"')) END,
    'would_freeze', CASE WHEN frz IS NOT NULL AND p_dry_run THEN frz END));
END $function$
$submitfn$;

  execute $checkerfn$
CREATE OR REPLACE FUNCTION public.v2_checker_action(p_key_id uuid, p_action text, p_args jsonb DEFAULT '{}'::jsonb, p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
DECLARE
  ik bots.ingest_keys; q public.v2_checker_queue; bot text; qid bigint; verdict text; reason text; sources jsonb;
  o jsonb; n jsonb; k text; v jsonb; conflicts text[] := '{}'; outcome text; pkcol text; res jsonb; lim int;
  firm_fields text[] := ARRAY['legal_name','founded_year','thesis_text','hq_street','hq_suite','hq_city','hq_state','hq_postal','hq_country','website_url','short_name'];
  drops jsonb; dropf text[]; drop_ok text[]; bad text; v_drop_col text; dropped jsonb; r jsonb; v_ap text;
BEGIN
  SELECT * INTO ik FROM bots.ingest_keys WHERE id = p_key_id AND active;
  IF NOT FOUND OR (ik.bot_id IS DISTINCT FROM 'toxy-checker' AND ik.bot_id IS DISTINCT FROM 'external-checker-1') THEN
    RETURN jsonb_build_object('ok',false,'error','only the Checker key may use this action'); END IF;
  bot := ik.bot_id;

  IF p_action = 'list_queue' THEN
    lim := LEAST(GREATEST(coalesce(CASE WHEN (p_args->>'limit') ~ '^\d+$' THEN (p_args->>'limit')::int END, 100), 1), 500);
    RETURN jsonb_build_object('ok',true,'bot_id',bot,'dry_run',p_dry_run,
      'pending',(SELECT count(*) FROM v2_checker_queue WHERE status='open' AND NOT archived),
      'items',coalesce((SELECT jsonb_agg(x ORDER BY (x->>'queue_id')::bigint) FROM (
        SELECT jsonb_build_object('queue_id',c.queue_id,'submission_id',c.submission_id,'firm_id',c.firm_id,'kind',c.kind,'table',c.table_name,
          'row_id',c.row_id,'old_value',c.old_value,'new_value',c.new_value,'created_at',c.created_at,
          'sent_by',(SELECT bk.bot_name FROM v2_research_submissions s JOIN v2_bot_keys bk ON bk.bot_key_id=s.bot_key_id WHERE s.submission_id=c.submission_id),
          'box',(SELECT s.target_box FROM v2_research_submissions s WHERE s.submission_id=c.submission_id)) x
        FROM v2_checker_queue c WHERE c.status='open' AND NOT c.archived ORDER BY c.queue_id LIMIT lim) t),'[]'));
  END IF;

  IF p_action <> 'verdict' THEN RETURN jsonb_build_object('ok',false,'error','action must be submit, list_queue or verdict'); END IF;
  qid := CASE WHEN (p_args->>'id') ~ '^\d+$' THEN (p_args->>'id')::bigint END;
  verdict := p_args->>'verdict'; reason := nullif(trim(coalesce(p_args->>'reason','')),''); sources := coalesce(p_args->'sources','[]');
  IF qid IS NULL THEN RETURN jsonb_build_object('ok',false,'error','id (queue_id number) required'); END IF;
  IF verdict IS NULL OR verdict NOT IN ('confirm','reject') THEN RETURN jsonb_build_object('ok',false,'error','verdict must be confirm or reject'); END IF;
  IF reason IS NULL THEN RETURN jsonb_build_object('ok',false,'error','reason required'); END IF;
  IF jsonb_typeof(sources) <> 'array' THEN RETURN jsonb_build_object('ok',false,'error','sources must be an array of links'); END IF;
  IF verdict = 'confirm' AND jsonb_array_length(sources) = 0 THEN RETURN jsonb_build_object('ok',false,'error','confirm needs at least one source link'); END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(sources) e WHERE coalesce(CASE WHEN jsonb_typeof(e)='object' THEN e->>'url' ELSE e#>>'{}' END,'') !~* '^(https?://)?(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(/[^\s]*)?$'
     OR coalesce(CASE WHEN jsonb_typeof(e)='object' THEN e->>'url' ELSE e#>>'{}' END,'') ~* '(google\.[a-z.]+/search|bing\.com/search|duckduckgo\.com/\?|grok\.com|x\.com/i/grok|chatgpt\.com|perplexity\.ai/search)') THEN
    RETURN jsonb_build_object('ok',false,'error','each source must be a real page link (not a search/chat page)'); END IF;

  SELECT * INTO q FROM v2_checker_queue WHERE queue_id = qid FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error',format('queue item %s not found', qid)); END IF;
  IF q.archived OR q.status <> 'open' THEN RETURN jsonb_build_object('ok',false,'error',format('queue item %s is not pending (status %s)', qid, q.status)); END IF;

  -- drop_fields (optional, confirm only): blank these optional details on the row and publish the rest.
  -- Strict allowlist; never the name, source fields, ids or foreign keys. Absent = old behavior.
  drops := p_args->'drop_fields';
  IF drops IS NOT NULL AND jsonb_typeof(drops) <> 'null' THEN
    IF verdict <> 'confirm' THEN RETURN jsonb_build_object('ok',false,'error','drop_fields only works with verdict confirm'); END IF;
    IF jsonb_typeof(drops) <> 'array' OR jsonb_array_length(drops) = 0
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(drops) e WHERE jsonb_typeof(e) <> 'string') THEN
      RETURN jsonb_build_object('ok',false,'error','drop_fields must be a non-empty list of field names'); END IF;
    SELECT array_agg(DISTINCT e ORDER BY e) INTO dropf FROM jsonb_array_elements_text(drops) e;
    drop_ok := CASE WHEN q.kind IN ('name-only','accepted-item') AND q.table_name = 'v2_people'
                    THEN ARRAY['x_url','x_followers','linkedin_url','linkedin_followers','photo_url'] ELSE '{}'::text[] END;
    SELECT string_agg(x, ', ') INTO bad FROM unnest(dropf) x WHERE NOT (x = ANY(drop_ok));
    IF bad IS NOT NULL THEN
      RETURN jsonb_build_object('ok',false,'error',format('drop_fields: cannot drop %s from %s (allowed: %s)', bad, q.table_name,
        coalesce(nullif(array_to_string(drop_ok, ', '), ''), 'none'))); END IF;
  END IF;

  BEGIN  -- rolled back at the end when p_dry_run
    pkcol := CASE q.table_name WHEN 'v2_funds' THEN 'fund_id' WHEN 'v2_startups' THEN 'startup_id' WHEN 'v2_people' THEN 'person_id'
                  WHEN 'v2_deals' THEN 'deal_id' WHEN 'v2_legal_items' THEN 'legal_item_id' WHEN 'v2_firms' THEN 'firm_id' WHEN 'v2_investor_principles' THEN 'id' WHEN 'v2_firm_stages' THEN 'id' WHEN 'v2_firm_industries' THEN 'id' WHEN 'firm_fund_announcements' THEN 'id' WHEN 'v2_firm_check_sizes' THEN 'id' ELSE 'row_id' END;
    IF verdict = 'reject' THEN
      -- Auto-published rows are taken down here, including a firm field that was already written.
      -- Anything the switch did not publish keeps the old archive path.
      v_ap := public.v2_auto_publish_checker_reject(qid, left('Checker rejected: '||reason, 300));
      IF v_ap IS NULL AND q.kind IN ('name-only','accepted-item') AND q.row_id IS NOT NULL AND q.table_name <> 'v2_firms' THEN
        EXECUTE format('UPDATE public.%I SET archived = true, archive_reason = $1 WHERE %I = $2', q.table_name, pkcol)
          USING left('Checker rejected: '||reason, 300), q.row_id;
      END IF;
      UPDATE v2_checker_queue SET status = 'failed' WHERE queue_id = qid;
      UPDATE v2_research_submissions SET status = left('Rejected: Checker: '||reason, 500) WHERE submission_id = q.submission_id;
      outcome := coalesce(v_ap, CASE WHEN q.kind IN ('name-only','accepted-item') AND q.table_name <> 'v2_firms' THEN 'Rejected: row archived, not published' ELSE 'Rejected: not applied' END);
    ELSIF q.kind IN ('name-only','accepted-item') THEN  -- R4.1: a passed item is published right away
      IF dropf IS NOT NULL THEN  -- blank only the dropped details, keep the rest
        EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE %I = $1 AND submission_id = $2', q.table_name, pkcol) INTO r USING q.row_id, q.submission_id;
        dropped := (SELECT jsonb_object_agg(x, r->x) FROM unnest(dropf) x);
        FOREACH v_drop_col IN ARRAY dropf LOOP
          EXECUTE format('UPDATE public.%I SET %I = NULL WHERE %I = $1 AND submission_id = $2', q.table_name, v_drop_col, pkcol) USING q.row_id, q.submission_id;
        END LOOP;
      END IF;
      UPDATE v2_checker_queue SET status = 'passed' WHERE queue_id = qid;
      outcome := public.v2_publish_queue_item(qid);
      IF dropf IS NOT NULL THEN outcome := outcome || ' (dropped: ' || array_to_string(dropf, ', ') || ')'; END IF;
    ELSIF q.kind = 'new-firm' THEN  -- only the publish step creates a firm (F1.3.1)
      UPDATE v2_checker_queue SET status = 'passed' WHERE queue_id = qid;
      UPDATE v2_research_submissions SET status = 'Held: Checker confirmed; new firm waits for the publish step (F1.3.1)' WHERE submission_id = q.submission_id;
      outcome := 'Confirmed: new firm waits for the publish step (F1.3.1)';
    ELSIF q.table_name = 'v2_startups' THEN
      BEGIN
        UPDATE public.v2_startups t SET website_url = q.new_value->>'website_url',
            website_source = q.new_value->'website_source'
          WHERE t.startup_id = q.row_id AND coalesce(t.website_url,'') = '' RETURNING to_jsonb(t) INTO n;
        IF n IS NULL THEN
          IF EXISTS (SELECT 1 FROM public.v2_auto_published ap WHERE ap.queue_id = qid)
             AND EXISTS (SELECT 1 FROM public.v2_startups t WHERE t.startup_id = q.row_id AND t.website_url IS NOT DISTINCT FROM (q.new_value->>'website_url')) THEN
            UPDATE public.v2_checker_queue SET status = 'passed' WHERE queue_id = qid;
            UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = q.submission_id;
            res := jsonb_build_object('website_url', q.new_value->>'website_url');
            outcome := 'Confirmed: website already filled';
          ELSE
            UPDATE public.v2_checker_queue SET status = 'held-for-alex' WHERE queue_id = qid;
            UPDATE public.v2_research_submissions SET status = 'Held: startup website was filled meanwhile' WHERE submission_id = q.submission_id;
            outcome := 'Held for Alex: startup website was filled meanwhile';
          END IF;
        ELSE
          UPDATE public.v2_checker_queue SET status = 'passed' WHERE queue_id = qid;
          UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = q.submission_id;
          res := jsonb_build_object('website_url', n->>'website_url');
          outcome := 'Confirmed: website filled';
        END IF;
      EXCEPTION WHEN unique_violation THEN
        UPDATE public.v2_checker_queue SET status = 'failed' WHERE queue_id = qid;
        UPDATE public.v2_research_submissions SET status = 'Rejected: another startup already has this website domain' WHERE submission_id = q.submission_id;
        outcome := 'Rejected: another startup already has this website domain';
      END;
    ELSE  -- changed-key-fact or empty firm field: never overwrite an existing value (P15)
      SELECT to_jsonb(f) INTO o FROM v2_firms f WHERE firm_id = q.firm_id;
      IF o IS NULL THEN RAISE EXCEPTION 'v2_checker: firm % not found', q.firm_id; END IF;
      FOR k, v IN SELECT * FROM jsonb_each(q.new_value) WHERE key = ANY(firm_fields) LOOP
        IF o->k IS NOT NULL AND o->k <> 'null'::jsonb AND (o->>k) IS DISTINCT FROM (v#>>'{}') THEN conflicts := conflicts || k; END IF;
      END LOOP;
      IF cardinality(conflicts) > 0 THEN
        UPDATE v2_checker_queue SET status = 'held-for-alex' WHERE queue_id = qid;
        UPDATE v2_research_submissions SET status = 'Held: Checker confirmed; changed key fact waits for Alex (P15)' WHERE submission_id = q.submission_id;
        outcome := 'Held for Alex: would overwrite existing key fact ('||array_to_string(conflicts,', ')||')';
      ELSE
        EXECUTE format('UPDATE public.v2_firms t SET (%s) = (SELECT %s FROM jsonb_populate_record(NULL::public.v2_firms, $1)), last_checked_date = current_date WHERE firm_id = $2 RETURNING to_jsonb(t)',
          (SELECT string_agg(format('%I',x),',') FROM jsonb_object_keys(q.new_value) x), (SELECT string_agg(format('%I',x),',') FROM jsonb_object_keys(q.new_value) x)) INTO n USING q.new_value, q.firm_id;
        UPDATE v2_checker_queue SET status = 'passed' WHERE queue_id = qid;
        UPDATE v2_research_submissions SET status = 'Accepted' WHERE submission_id = q.submission_id;
        res := (SELECT jsonb_object_agg(x, n->x) FROM jsonb_object_keys(q.new_value) x);
        outcome := 'Confirmed: applied (fields were empty or unchanged)';
      END IF;
    END IF;
    INSERT INTO v2_checker_verdicts (queue_id, submission_id, actor, verdict, reason, sources, outcome)
      VALUES (qid, q.submission_id, bot, verdict, reason, sources, outcome);
    INSERT INTO v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
      VALUES (bot, q.firm_id, coalesce((SELECT target_box FROM v2_research_submissions WHERE submission_id=q.submission_id),'?'), q.table_name, q.row_id, q.submission_id,
              CASE WHEN res IS NOT NULL THEN (SELECT jsonb_object_agg(x, o->x) FROM jsonb_object_keys(q.new_value) x) ELSE q.old_value END,
              jsonb_build_object('checker_verdict',verdict,'outcome',outcome,'queue_id',qid,'reason',reason,'sources',sources,'applied',res)
                || CASE WHEN dropped IS NOT NULL THEN jsonb_build_object('dropped',dropped) ELSE '{}'::jsonb END, left(CASE WHEN verdict = 'reject' THEN 'Rejected: Checker: '||reason
                   WHEN outcome LIKE 'Confirmed: applied%' OR q.kind IN ('name-only','accepted-item') THEN 'Accepted'
                   ELSE 'Blocked: Checker confirmed; '||outcome END, 500));
    IF p_dry_run THEN RAISE EXCEPTION 'v2_dry_run_rollback'; END IF;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'v2_dry_run_rollback' THEN RETURN jsonb_build_object('ok',false,'error',SQLERRM); END IF;
  END;
  RETURN jsonb_strip_nulls(jsonb_build_object('ok',true,'bot_id',bot,'dry_run',p_dry_run,'queue_id',qid,'kind',q.kind,'verdict',verdict,'outcome',outcome,
    'applied',res,'dropped',dropped,'note',CASE WHEN p_dry_run THEN 'dry run: nothing saved' END));
END $function$
$checkerfn$;

  execute 'revoke all on function public.v2_auto_publish_on(bigint) from public';
  execute 'revoke all on function public.v2_auto_publish_pk(text) from public';
  execute 'revoke all on function public.v2_auto_publish_allowed(text) from public';
  execute 'revoke all on function public.v2_auto_publish_log(bigint, text, jsonb) from public';
  execute 'revoke all on function public.v2_auto_publish_shared(text, bigint, bigint) from public';
  execute 'revoke all on function public.v2_auto_publish_write_firm(bigint, jsonb) from public';
  execute 'revoke all on function public.v2_auto_publish_field_patch(jsonb, jsonb, text) from public';
  execute 'revoke all on function public.v2_auto_publish_show_row(text, bigint) from public';
  execute 'revoke all on function public.v2_auto_publish_hide_row(text, bigint, boolean, text) from public';
  execute 'revoke all on function public.v2_auto_publish_apply_queue(bigint) from public';
  execute 'revoke all on function public.v2_auto_publish_apply_submission(bigint) from public';
  execute 'revoke all on function public.v2_auto_publish_take_down(bigint, text, text) from public';
  execute 'revoke all on function public.v2_auto_publish_checker_reject(bigint, text) from public';
  execute 'revoke all on function public.v2_auto_publish_restore_one(bigint) from public';
  execute 'revoke all on function public.v2_auto_publish_set(boolean, bigint[]) from public';
  execute 'revoke all on function public.v2_auto_publish_backfill(bigint) from public';
  execute 'revoke all on function public.v2_auto_publish_scope(bigint, bigint, timestamptz, timestamptz) from public';
  execute 'revoke all on function public.v2_auto_publish_pull(bigint, bigint, timestamptz, timestamptz) from public';
  execute 'revoke all on function public.v2_auto_publish_restore(bigint, bigint, timestamptz, timestamptz) from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on table public.v2_auto_publish from anon, authenticated';
    execute 'revoke all on table public.v2_auto_published from anon, authenticated';
    execute 'revoke all on function public.v2_auto_publish_on(bigint) from anon, authenticated';
    execute 'revoke all on function public.v2_auto_publish_pk(text) from anon, authenticated';
    execute 'revoke all on function public.v2_auto_publish_allowed(text) from anon, authenticated';
    execute 'revoke all on function public.v2_auto_publish_log(bigint, text, jsonb) from anon, authenticated';
    execute 'revoke all on function public.v2_auto_publish_shared(text, bigint, bigint) from anon, authenticated';
    execute 'revoke all on function public.v2_auto_publish_write_firm(bigint, jsonb) from anon, authenticated';
    execute 'revoke all on function public.v2_auto_publish_field_patch(jsonb, jsonb, text) from anon, authenticated';
    execute 'revoke all on function public.v2_auto_publish_show_row(text, bigint) from anon, authenticated';
    execute 'revoke all on function public.v2_auto_publish_hide_row(text, bigint, boolean, text) from anon, authenticated';
    execute 'revoke all on function public.v2_auto_publish_apply_queue(bigint) from anon, authenticated';
    execute 'revoke all on function public.v2_auto_publish_apply_submission(bigint) from anon, authenticated';
    execute 'revoke all on function public.v2_auto_publish_take_down(bigint, text, text) from anon, authenticated';
    execute 'revoke all on function public.v2_auto_publish_checker_reject(bigint, text) from anon, authenticated';
    execute 'revoke all on function public.v2_auto_publish_restore_one(bigint) from anon, authenticated';
    execute 'revoke all on function public.v2_auto_publish_set(boolean, bigint[]) from anon, authenticated';
    execute 'revoke all on function public.v2_auto_publish_backfill(bigint) from anon, authenticated';
    execute 'revoke all on function public.v2_auto_publish_scope(bigint, bigint, timestamptz, timestamptz) from anon, authenticated';
    execute 'revoke all on function public.v2_auto_publish_pull(bigint, bigint, timestamptz, timestamptz) from anon, authenticated';
    execute 'revoke all on function public.v2_auto_publish_restore(bigint, bigint, timestamptz, timestamptz) from anon, authenticated';
  end if;
  if exists (select 1 from pg_roles where rolname = 'bot_writer') then
    execute 'revoke all on function public.v2_auto_publish_on(bigint) from bot_writer';
    execute 'revoke all on function public.v2_auto_publish_pk(text) from bot_writer';
    execute 'revoke all on function public.v2_auto_publish_allowed(text) from bot_writer';
    execute 'revoke all on function public.v2_auto_publish_log(bigint, text, jsonb) from bot_writer';
    execute 'revoke all on function public.v2_auto_publish_shared(text, bigint, bigint) from bot_writer';
    execute 'revoke all on function public.v2_auto_publish_write_firm(bigint, jsonb) from bot_writer';
    execute 'revoke all on function public.v2_auto_publish_field_patch(jsonb, jsonb, text) from bot_writer';
    execute 'revoke all on function public.v2_auto_publish_show_row(text, bigint) from bot_writer';
    execute 'revoke all on function public.v2_auto_publish_hide_row(text, bigint, boolean, text) from bot_writer';
    execute 'revoke all on function public.v2_auto_publish_apply_queue(bigint) from bot_writer';
    execute 'revoke all on function public.v2_auto_publish_apply_submission(bigint) from bot_writer';
    execute 'revoke all on function public.v2_auto_publish_take_down(bigint, text, text) from bot_writer';
    execute 'revoke all on function public.v2_auto_publish_checker_reject(bigint, text) from bot_writer';
    execute 'revoke all on function public.v2_auto_publish_restore_one(bigint) from bot_writer';
    execute 'revoke all on function public.v2_auto_publish_set(boolean, bigint[]) from bot_writer';
    execute 'revoke all on function public.v2_auto_publish_backfill(bigint) from bot_writer';
    execute 'revoke all on function public.v2_auto_publish_scope(bigint, bigint, timestamptz, timestamptz) from bot_writer';
    execute 'revoke all on function public.v2_auto_publish_pull(bigint, bigint, timestamptz, timestamptz) from bot_writer';
    execute 'revoke all on function public.v2_auto_publish_restore(bigint, bigint, timestamptz, timestamptz) from bot_writer';
    execute 'revoke all on table public.v2_auto_publish from bot_writer';
    execute 'revoke all on table public.v2_auto_published from bot_writer';
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant select, insert, update, delete on table public.v2_auto_publish to service_role';
    execute 'grant select, insert, update, delete on table public.v2_auto_published to service_role';
    execute 'grant execute on function public.v2_auto_publish_set(boolean, bigint[]) to service_role';
    execute 'grant execute on function public.v2_auto_publish_backfill(bigint) to service_role';
    execute 'grant execute on function public.v2_auto_publish_pull(bigint, bigint, timestamptz, timestamptz) to service_role';
    execute 'grant execute on function public.v2_auto_publish_restore(bigint, bigint, timestamptz, timestamptz) to service_role';
  end if;
end
$mig$;
