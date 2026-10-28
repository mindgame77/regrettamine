-- Rollback for 20261028020000_lab_deals.sql.
-- Drops the lab-only deal trigger and helpers. Does not delete investments or portfolio companies.

drop trigger if exists lab_timeline_deal on public.timeline_events;
drop function if exists public._lab_timeline_deal();
drop function if exists public._lab_save_deal(uuid, text, text, numeric, date, text);
drop function if exists public._deal_from_text(text);
