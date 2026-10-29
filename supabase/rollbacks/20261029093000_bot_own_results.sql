-- Rollback for 20261029093000_bot_own_results.sql.
-- 1. Redeploy research-ingest from supabase/rollbacks/20261029093000_research_ingest_v30.ts (the live version 30
--    source taken before this change), verify_jwt false. Do this first: the new function calls these readers.
-- 2. Run this file. No data is touched.
drop function if exists public.research_my_results(uuid, int, int);
drop function if exists public.research_entry_result(bigint);
