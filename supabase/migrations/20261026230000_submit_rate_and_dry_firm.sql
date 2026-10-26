-- Per-bot upload cap, and per-firm changed-only publish dry runs.
--  * research_submit: at most 20 rows per bot_id in the last minute. The next one raises
--    'rate_limited: max 20 uploads per minute per bot, retry shortly' and inserts nothing.
--  * Dry run stays the same check (_publish_firm inside the same rollback). It no longer
--    wipes the batch. dry_run_publish_firm replaces one firm's dry row. dry_run_publish_batch
--    takes at most p_limit firms (default 1) from the changed list and reports how many remain.
--  * A firm is changed when it has no dry row, or a submission, enrichment, or firm edit is
--    newer than that row's checked_at. A firm edit is the firm row, an in-place edit backup
--    (not a publish/undo backup), a hide, or a press-link / review update.

create index if not exists research_submissions_bot_received_idx
  on public.research_submissions (bot_id, received_at);

alter table public.publish_batch_firms add column if not exists checked_at timestamptz;
update public.publish_batch_firms set checked_at = created_at where checked_at is null;
alter table public.publish_batch_firms alter column checked_at set default now();
alter table public.publish_batch_firms alter column checked_at set not null;

-- Latest time a person changed this firm's live page (not a bot upload, and not this dry run's own backups).
create or replace function public._firm_edit_at(p_firm uuid) returns timestamptz
language sql stable security definer set search_path = public as $$
  select max(t) from (
    select updated_at as t from firms where id = p_firm
    union all
    select max(saved_at) from cleanup_backup
     where firm_id = p_firm and batch !~ '^(publish|undo):'
    union all select max(hidden_at) from firm_profile_facts where firm_id = p_firm
    union all select max(hidden_at) from firm_legal_items where firm_id = p_firm
    union all select max(hidden_at) from timeline_events where firm_id = p_firm
    union all select max(hidden_at) from firm_people_roles where firm_id = p_firm
    union all select max(hidden_at) from press_item_firms where firm_id = p_firm
    union all select max(updated_at) from press_item_firms where firm_id = p_firm
    union all select max(updated_at) from reviews where firm_id = p_firm
  ) s $$;

-- Firms in this batch with no dry row, or with newer submissions, enrichments, or firm edits.
create or replace function public._publish_changed_firms(p_id text) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(f.id order by f.ord), '{}')
    from publish_batches b
    cross join lateral unnest(b.firm_ids) with ordinality as f(id, ord)
    join firms fm on fm.id = f.id
    left join lateral (
      select max(d.checked_at) as checked_at
        from publish_batch_firms d
       where d.batch_id = b.id and d.firm_id = f.id and d.phase = 'dry'
    ) d on true
   where b.id = p_id
     and (
       d.checked_at is null
       or exists (
         select 1 from research_submissions s
          where s.received_at > d.checked_at
            and s.registry_id = coalesce(fm.registry_id, _firm_queue_id(fm.id)))
       or exists (
         select 1 from research_enrichments e
          where e.received_at > d.checked_at
            and (e.firm_id = fm.id or (fm.registry_id is not null and e.registry_id = fm.registry_id)))
       or _firm_edit_at(fm.id) > d.checked_at
     ) $$;

create or replace function public.research_submit(p_id text, p_bot text, p_payload jsonb, p_count int, p_valid boolean, p_errors jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  q research_queue;
  s_id bigint;
  v_holder boolean;
  v_prior boolean;
  v_recent int;
begin
  select count(*) into v_recent from research_submissions
   where bot_id = p_bot and received_at > now() - interval '1 minute';
  if v_recent >= 20 then
    raise exception 'rate_limited: max 20 uploads per minute per bot, retry shortly';
  end if;
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

-- One firm, same publish and same rollback as the old batch dry run. Replaces only that firm's dry row.
-- set local statement_timeout limits the check. pg_try_advisory_xact_lock is the transaction-scoped
-- form of pg_try_advisory_lock: only one dry run at a time, and the lock ends with the transaction
-- (a session lock would stick on a pooled connection).
create or replace function public.dry_run_publish_firm(p_id text, p_firm uuid) returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare b publish_batches; r jsonb;
begin
  select * into b from publish_batches where id = p_id;
  if b.id is null then raise exception 'no batch %', p_id; end if;
  if b.status <> 'draft' then raise exception 'batch % is %, dry runs only for draft batches', p_id, b.status; end if;
  if not p_firm = any(b.firm_ids) then raise exception 'firm % is not in batch %', p_firm, p_id; end if;
  set local statement_timeout = '20s';
  if not pg_try_advisory_xact_lock(hashtext('regretamin.dry_run_publish')::bigint) then
    raise exception 'dry run already in progress';
  end if;
  begin
    r := _publish_firm(p_id, b.source, p_firm);
    raise exception using errcode = 'P0001', message = 'dryrun-rollback';
  exception when others then
    if sqlerrm <> 'dryrun-rollback' then r := jsonb_build_object('decision', 'held', 'reasons', jsonb_build_array('error: ' || sqlerrm)); end if;
  end;
  delete from publish_batch_firms where batch_id = p_id and firm_id = p_firm and phase = 'dry';
  insert into publish_batch_firms(batch_id, firm_id, phase, decision, reasons, items, checked_at)
  values (p_id, p_firm, 'dry', r->>'decision',
    array(select jsonb_array_elements_text(coalesce(r->'reasons', '[]'::jsonb))),
    r - 'decision' - 'reasons', now());
  update publish_batches set dry_run_at = now(), dry_report = publish_batch_summary(p_id, 'dry') where id = p_id;
  return jsonb_build_object('batch', p_id, 'firm', p_firm, 'decision', r->>'decision', 'reasons', coalesce(r->'reasons', '[]'::jsonb));
end $fn$;

-- Changed firms only, at most p_limit (default 1). Does not delete other firms' dry rows.
-- Returns how many were checked, how many changed firms are still waiting, and the next firm id.
create or replace function public.dry_run_publish_batch(p_id text, p_from int default 1, p_limit int default 1)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare
  b publish_batches; changed uuid[]; slice uuid[]; f uuid; i int := 0; n int; nxt uuid;
begin
  select * into b from publish_batches where id = p_id;
  if b.id is null then raise exception 'no batch %', p_id; end if;
  if b.status <> 'draft' then raise exception 'batch % is %, dry runs only for draft batches', p_id, b.status; end if;
  if p_from < 1 then p_from := 1; end if;
  if p_limit < 1 then p_limit := 1; end if;
  changed := _publish_changed_firms(p_id);
  n := coalesce(cardinality(changed), 0);
  if n >= p_from then
    slice := changed[p_from : least(n, p_from + p_limit - 1)];
  end if;
  if slice is null then slice := '{}'; end if;
  foreach f in array slice loop
    perform dry_run_publish_firm(p_id, f);
    i := i + 1;
  end loop;
  update publish_batches set dry_run_at = now(), dry_report = publish_batch_summary(p_id, 'dry') where id = p_id;
  if p_from + i <= n then nxt := changed[p_from + i]; end if;
  return jsonb_build_object(
    'batch', p_id,
    'firms_checked', i,
    'remaining', greatest(n - (p_from - 1) - i, 0),
    'next', nxt);
end $fn$;

revoke execute on function public._firm_edit_at(uuid), public._publish_changed_firms(text), public.dry_run_publish_firm(text, uuid)
  from public, anon, authenticated;
