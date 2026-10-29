-- Rollback for 20261029050000_entry_check_layer1.sql: removes the Layer 1 entry check trigger, functions and columns.
-- The stored door-check results are internal only (A4.6) and are dropped with the columns.
drop trigger if exists aa_entry_check on bots.research_submissions;
drop function if exists bots.entry_check_trg();
drop function if exists bots.entry_check_purge();
drop function if exists public._entry_check(bigint, text, text, jsonb);
drop function if exists public._entry_duplicate(bigint, text, text, jsonb);
drop function if exists public._entry_check_reasons(jsonb, text);
drop function if exists public._entry_level(jsonb, jsonb);
drop function if exists public._entry_date_ok(text);
drop function if exists public._entry_status_bad(jsonb);
drop function if exists public._entry_section(text, text);
alter table bots.research_submissions
  drop column if exists entry_link_open_pending,
  drop column if exists entry_check_at,
  drop column if exists entry_check;
