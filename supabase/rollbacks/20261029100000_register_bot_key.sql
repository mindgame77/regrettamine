-- Rollback for 20261029100000_register_bot_key.sql. Drops the function only; keys it created stay and keep working.
-- To retire a key made by it: update bots.ingest_keys set active = false where name = 'bot-<bot_id>-<stamp>';
drop function if exists public.register_bot_key(text, text);
