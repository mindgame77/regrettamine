-- Turns the Checker back off. Lab enrich writes the page again, the same as a non-lab firm.
-- Drops the automatic submission trigger. Does not put back exact copies that were already removed.
-- The earlier Checker rollback file is unchanged: supabase/rollbacks/20261028070000_checker_switch.sql

update bots.ingest_settings set value = 'false' where key = 'checker_publish';

drop trigger if exists checker_on_submission on bots.research_submissions;
drop function if exists public.checker_on_submission();
drop function if exists public.checker_publish_submission(bigint);
drop function if exists public._checker_payload_items(jsonb);
drop function if exists public._checker_place(uuid, text, jsonb, text, smallint, int, bigint);
drop function if exists public._checker_keep_one_exact(uuid);
drop function if exists public._checker_note(uuid, text, bigint, text, text, text);
drop function if exists public._checker_item_text(text, jsonb);
drop function if exists public._checker_url_key(text);
