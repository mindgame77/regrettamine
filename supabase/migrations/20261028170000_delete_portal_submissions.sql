-- Delete the friend's (portal-*) bot uploads from bots.research_submissions.
-- Keeps our own bots (toxy-researcher-2/3, toxy-dev-*, toxy-enricher).
-- Pre-check (2026-10-28): 4,675 portal rows, none for the 10 lab firms;
-- 0 bots.fact_source_additions rows cascade; bots.firm_lps.submission_id is set NULL
-- for 3,839 non-lab rows (rows themselves kept).
-- ROLLBACK: not restorable; the deleted raw payloads are gone (accepted by Alex).
-- Follow-up (manual, outside a transaction): VACUUM FULL bots.research_submissions;
delete from bots.research_submissions where bot_id like 'portal-%';
