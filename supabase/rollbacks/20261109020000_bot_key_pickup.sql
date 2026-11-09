-- Rollback for 20261109020000_bot_key_pickup.sql.
-- Drops the pickup table and functions. bots.ingest_keys is not changed.
-- A key that was sealed and not yet delivered is no longer stored here. The key file is unchanged.
-- A key the bot already saved still works. Apply the migration again and seal that file to retry pickup.

drop function if exists public.pending_bot_key_pickups();
drop function if exists public.clear_bot_key_pickup(text);
drop function if exists public.approve_bot_key_pickup(text);
drop function if exists public.bot_key_apply(text, text);
drop function if exists public.seal_bot_key_pickup(text, text);

drop table if exists bots.bot_key_pickup;
