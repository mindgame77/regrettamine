-- One-time pickup for a research key that is already registered.
-- The bot applies with a proof it keeps. The owner approves once. The same key is returned once,
-- then removed from bot_key_pickup. bots.ingest_keys is not altered: hash, rate limit, and active stay.
-- portal-night-bot is refused and gets no pickup row.
-- bot_key_pickup has no grants. The door calls the functions. It does not read this table.
-- A later "grant on all tables in schema bots" would expose this table. Do not add one.
-- Rollback: supabase/rollbacks/20261109020000_bot_key_pickup.sql

create table bots.bot_key_pickup (
  key_id uuid primary key references bots.ingest_keys(id) on delete cascade,
  pickup_key text,
  proof_hash text,
  status text,
  applied_at timestamptz,
  constraint bot_key_pickup_status check (status is null or status in ('pending', 'approved', 'delivered')),
  constraint bot_key_pickup_wiped check (status is distinct from 'delivered' or pickup_key is null),
  constraint bot_key_pickup_proof check (proof_hash is null or proof_hash ~ '^[0-9a-f]{64}$')
);

comment on table bots.bot_key_pickup is
  'Sealed copy of an existing research key for one HTTPS pickup. Empty after the bot takes it.';
comment on column bots.bot_key_pickup.pickup_key is
  'Existing research key until delivery. Do not select this column.';
comment on column bots.bot_key_pickup.proof_hash is
  'sha256 hex of the proof the bot kept. Not the proof, and not the research key.';

alter table bots.bot_key_pickup enable row level security;
revoke all on table bots.bot_key_pickup from public, anon, authenticated, bot_writer, service_role;

-- Owner only. Checks the hash, stores the existing key, and does not return it.
-- A delivered row can be sealed again after a lost reply. That still needs a new apply and a new approval.
create or replace function public.seal_bot_key_pickup(p_bot_id text, p_key text)
returns jsonb language plpgsql volatile security definer set search_path = bots, public as $$
declare k ingest_keys; p bot_key_pickup; n int; v_hash text;
begin
  if p_bot_id is null or p_bot_id !~ '^[a-z0-9][a-z0-9-]{2,62}$' or p_bot_id like 'portal-night%' then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_key is null or length(p_key) < 20 or length(p_key) > 200 or p_key !~ '^[A-Za-z0-9_-]+$' then
    return jsonb_build_object('ok', false, 'error', 'refused');
  end if;
  perform pg_advisory_xact_lock(hashtext('bot_key_pickup:' || p_bot_id));
  select count(*) into n from ingest_keys where bot_id = p_bot_id and active;
  if n <> 1 then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  select * into k from ingest_keys where bot_id = p_bot_id and active for update;
  v_hash := encode(extensions.digest(p_key, 'sha256'), 'hex');
  if v_hash is distinct from k.key_hash then
    return jsonb_build_object('ok', false, 'error', 'refused');
  end if;
  select * into p from bot_key_pickup where key_id = k.id for update;
  if not found then
    insert into bot_key_pickup (key_id, pickup_key) values (k.id, p_key);
    return jsonb_build_object('ok', true, 'bot_id', p_bot_id, 'status', 'sealed');
  end if;
  if p.status = 'delivered' then
    update bot_key_pickup
       set pickup_key = p_key, proof_hash = null, status = null, applied_at = null
     where key_id = k.id and status = 'delivered';
    return jsonb_build_object('ok', true, 'bot_id', p_bot_id, 'status', 'sealed');
  end if;
  if p.pickup_key is not null and p.pickup_key is distinct from p_key then
    return jsonb_build_object('ok', false, 'error', 'refused');
  end if;
  if p.pickup_key is not null then
    return jsonb_build_object('ok', true, 'bot_id', p_bot_id, 'status', coalesce(p.status, 'sealed'));
  end if;
  update bot_key_pickup set pickup_key = p_key where key_id = k.id and pickup_key is null;
  return jsonb_build_object('ok', true, 'bot_id', p_bot_id, 'status', 'sealed');
end $$;

-- Bot door. p_proof_hash is sha256 of the proof. The proof itself is not stored.
-- The key is returned only when this proof was approved and the row has not been delivered.
create or replace function public.bot_key_apply(p_bot_id text, p_proof_hash text)
returns jsonb language plpgsql volatile security definer set search_path = bots, public as $$
declare k ingest_keys; p bot_key_pickup; n int; v_key text;
begin
  if p_bot_id is null or p_bot_id !~ '^[a-z0-9][a-z0-9-]{2,62}$' or p_bot_id like 'portal-night%'
     or p_proof_hash is null or p_proof_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  perform pg_advisory_xact_lock(hashtext('bot_key_pickup:' || p_bot_id));
  select count(*) into n from ingest_keys where bot_id = p_bot_id and active;
  if n <> 1 then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  select * into k from ingest_keys where bot_id = p_bot_id and active for update;
  if not exists (select 1 from bot_key_pickup where key_id = k.id) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  select * into p from bot_key_pickup where key_id = k.id for update;
  if p.status = 'delivered' then
    return jsonb_build_object('ok', false, 'error', 'already_delivered');
  end if;
  if p.pickup_key is null or length(p.pickup_key) = 0 then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p.status is null then
    update bot_key_pickup
       set proof_hash = p_proof_hash, status = 'pending', applied_at = now()
     where key_id = k.id;
    return jsonb_build_object('ok', true, 'status', 'pending', 'proof_prefix', left(p_proof_hash, 8));
  end if;
  if p.status = 'pending' then
    if p.proof_hash is distinct from p_proof_hash then
      return jsonb_build_object('ok', false, 'error', 'pending_locked');
    end if;
    return jsonb_build_object('ok', true, 'status', 'pending', 'proof_prefix', left(p_proof_hash, 8));
  end if;
  if p.status = 'approved' then
    if p.proof_hash is distinct from p_proof_hash then
      return jsonb_build_object('ok', false, 'error', 'unauthorized');
    end if;
    v_key := p.pickup_key;
    update bot_key_pickup
       set pickup_key = null, proof_hash = null, status = 'delivered'
     where key_id = k.id and status = 'approved';
    return jsonb_build_object('ok', true, 'status', 'delivered', 'key', v_key);
  end if;
  return jsonb_build_object('ok', false, 'error', 'unauthorized');
end $$;

create or replace function public.approve_bot_key_pickup(p_bot_id text)
returns jsonb language plpgsql volatile security definer set search_path = bots, public as $$
declare k ingest_keys; p bot_key_pickup; n int;
begin
  if p_bot_id is null or p_bot_id !~ '^[a-z0-9][a-z0-9-]{2,62}$' or p_bot_id like 'portal-night%' then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  perform pg_advisory_xact_lock(hashtext('bot_key_pickup:' || p_bot_id));
  select count(*) into n from ingest_keys where bot_id = p_bot_id and active;
  if n <> 1 then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  select * into k from ingest_keys where bot_id = p_bot_id and active for update;
  select * into p from bot_key_pickup where key_id = k.id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_pending');
  end if;
  if p.status = 'delivered' then
    return jsonb_build_object('ok', false, 'error', 'already_delivered');
  end if;
  if p.status = 'approved' and p.pickup_key is not null and p.proof_hash is not null then
    return jsonb_build_object('ok', true, 'bot_id', p_bot_id, 'status', 'approved');
  end if;
  if p.status is distinct from 'pending' or p.pickup_key is null or p.proof_hash is null then
    return jsonb_build_object('ok', false, 'error', 'not_pending');
  end if;
  update bot_key_pickup set status = 'approved' where key_id = k.id and status = 'pending';
  return jsonb_build_object('ok', true, 'bot_id', p_bot_id, 'status', 'approved');
end $$;

-- Drops a pending or approved proof so the right bot can apply. Does not return or remove the sealed key.
create or replace function public.clear_bot_key_pickup(p_bot_id text)
returns jsonb language plpgsql volatile security definer set search_path = bots, public as $$
declare k ingest_keys; p bot_key_pickup; n int;
begin
  if p_bot_id is null or p_bot_id !~ '^[a-z0-9][a-z0-9-]{2,62}$' or p_bot_id like 'portal-night%' then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  perform pg_advisory_xact_lock(hashtext('bot_key_pickup:' || p_bot_id));
  select count(*) into n from ingest_keys where bot_id = p_bot_id and active;
  if n <> 1 then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  select * into k from ingest_keys where bot_id = p_bot_id and active for update;
  select * into p from bot_key_pickup where key_id = k.id for update;
  if not found or p.pickup_key is null then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p.status = 'delivered' then
    return jsonb_build_object('ok', false, 'error', 'already_delivered');
  end if;
  update bot_key_pickup
     set proof_hash = null, status = null, applied_at = null
   where key_id = k.id and status is distinct from 'delivered';
  return jsonb_build_object('ok', true, 'bot_id', p_bot_id, 'status', 'cleared');
end $$;

create or replace function public.pending_bot_key_pickups()
returns table (bot_id text, status text, applied_at timestamptz, proof_prefix text)
language sql stable security definer set search_path = bots, public as $$
  select k.bot_id, p.status, p.applied_at, left(p.proof_hash, 8)
    from bot_key_pickup p
    join ingest_keys k on k.id = p.key_id
   where k.active
     and p.status in ('pending', 'approved')
     and k.bot_id not like 'portal-night%'
   order by p.applied_at nulls last, k.bot_id;
$$;

revoke all on function public.seal_bot_key_pickup(text, text) from public, anon, authenticated;
revoke all on function public.bot_key_apply(text, text) from public, anon, authenticated;
revoke all on function public.approve_bot_key_pickup(text) from public, anon, authenticated;
revoke all on function public.clear_bot_key_pickup(text) from public, anon, authenticated;
revoke all on function public.pending_bot_key_pickups() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'bot_writer') then
    revoke all on function public.seal_bot_key_pickup(text, text) from bot_writer;
    revoke all on function public.bot_key_apply(text, text) from bot_writer;
    revoke all on function public.approve_bot_key_pickup(text) from bot_writer;
    revoke all on function public.clear_bot_key_pickup(text) from bot_writer;
    revoke all on function public.pending_bot_key_pickups() from bot_writer;
  end if;
end $$;

grant execute on function public.seal_bot_key_pickup(text, text) to service_role;
grant execute on function public.bot_key_apply(text, text) to service_role;
grant execute on function public.approve_bot_key_pickup(text) to service_role;
grant execute on function public.clear_bot_key_pickup(text) to service_role;
grant execute on function public.pending_bot_key_pickups() to service_role;
