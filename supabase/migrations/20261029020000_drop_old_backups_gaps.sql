-- Delete the rest of the original cleanup list. Approved by Alex 2026-10-28 09:49 PT, no backup copy.
-- Rollback (empty structures): supabase/rollbacks/20261029020000_drop_old_backups_gaps.sql

-- 1) bots.research_gaps (~64 MB). The upload trigger that wrote it goes too; the two bot RPCs stay as empty stubs.
drop trigger if exists research_gaps_from_submission on bots.research_submissions;
drop function if exists public.research_gaps_sync();
drop table if exists bots.research_gaps cascade;
create or replace function public.research_gaps_list(p_registry text, p_limit integer) returns jsonb
language sql security definer set search_path = bots, public as $$ select '[]'::jsonb $$;
create or replace function public.research_claim_gaps(p_bot text, p_registry text) returns jsonb
language sql security definer set search_path = bots, public as $$ select jsonb_build_object('ok', false, 'error', 'gaps retired') $$;
revoke all on function public.research_gaps_list(text, integer) from public, anon, authenticated;
revoke all on function public.research_claim_gaps(text, text) from public, anon, authenticated;

-- 2) Old backup tables and the ID map.
drop schema if exists backup_20261024s12 cascade;
do $$ declare r record; begin
  for r in select n.nspname s, c.relname t from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where c.relkind = 'r' and n.nspname = 'public' and (c.relname like '\_bak\_%' or c.relname like '%\_bak\_pre\_%') loop
    execute format('drop table if exists %I.%I cascade', r.s, r.t);
  end loop;
end $$;
drop table if exists public.activity_legacy_map cascade;
-- Live undo journals still written by publish/edit functions: emptied, structure kept.
truncate public.cleanup_backup, public.home_held_backup, public.lab_cap_archive;

-- 3) The 2 no-op triggers.
drop trigger if exists aa_ensure_firm on bots.research_submissions;
drop trigger if exists zz_stamp_firm_report on bots.research_submissions;
drop function if exists public.ensure_firm_trg();
drop function if exists public.stamp_firm_report_trg();

-- 4) The 9 old score rows (parts/lines/inputs cascade).
delete from public.score_results;

-- 5) The 10 Sequoia deals with no source.
delete from public.investments i using public.firms f
 where f.id = i.firm_id and f.slug = 'sequoia' and i.source_system = 'sequoia-timeline-deal'
   and coalesce(cardinality(i.source_urls), 0) = 0;
