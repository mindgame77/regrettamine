-- One ingest key per uploading bot (Alex, 2026-10-28). Additive only: no existing key is changed or revoked.
-- public.register_bot_key(bot_id, sha256 hex of the raw key) adds a key linked to that bot. The raw key never
-- reaches the database: scripts/new_bot_key.py makes it on the box, writes it to /home/box/regretamin-keys/<bot_id>.key
-- (chmod 600) and sends only the hash. The same sha256 is what research-ingest checks (ingest_auth).
-- Refuses: a malformed bot_id or hash, a hash already in use, a bot that already has an active key linked to it.
-- Server only (A14.6): fixed search_path, no EXECUTE for public/anon/authenticated; service_role only.
-- Rollback: supabase/rollbacks/20261029100000_register_bot_key.sql

create or replace function public.register_bot_key(p_bot_id text, p_hash text)
 returns jsonb language plpgsql volatile security definer set search_path = bots, public as $$
declare v_id uuid; v_name text;
begin
  if p_bot_id is null or p_bot_id !~ '^[a-z0-9][a-z0-9-]{2,62}$' then
    return jsonb_build_object('ok', false, 'error', 'bot_id must be 3-63 characters: lowercase letters, digits, hyphens');
  end if;
  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok', false, 'error', 'hash must be the 64-character lowercase sha256 hex of the key');
  end if;
  perform pg_advisory_xact_lock(hashtext('register_bot_key:' || p_bot_id));
  if exists (select 1 from ingest_keys where bot_id = p_bot_id and active) then
    return jsonb_build_object('ok', false, 'error', 'this bot already has an active key');
  end if;
  if exists (select 1 from ingest_keys where key_hash = p_hash) then
    return jsonb_build_object('ok', false, 'error', 'this hash is already in use; make a new key');
  end if;
  v_name := 'bot-' || p_bot_id || '-' || to_char(now() at time zone 'America/Los_Angeles', 'YYYY-MM-DD-HH24MISS');
  insert into ingest_keys (name, key_hash, active, bot_id) values (v_name, p_hash, true, p_bot_id) returning id into v_id;
  return jsonb_build_object('ok', true, 'key_id', v_id, 'bot_id', p_bot_id, 'name', v_name);
end $$;

revoke all on function public.register_bot_key(text, text) from public, anon, authenticated;
grant execute on function public.register_bot_key(text, text) to service_role;
