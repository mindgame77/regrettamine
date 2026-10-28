-- Rollback for 20261028050000_sequoia_timeline_deals.sql.
-- Drops the dry-run function. Does not delete investments copied from timeline rows.

drop function if exists public.sequoia_timeline_deals(boolean);
