-- Rollback for 20261014130000_data_status, 20261014140000_merge_ready, 20261014150000_vc_profiles
-- (and the a16z benchmark load). Not run by CI. Run in one transaction:  psql -1 -f this_file
-- Drops only objects these migrations created; existing content rows are untouched
-- (added columns are dropped, their values lost). Full data backup: toxybase/backups/2026-10-14/.

-- vc_profiles layer
drop view if exists public.vc_profile_completeness;
drop view if exists public.vc_profiles;
drop table if exists public.vc_score_inputs, public.vc_score_parts, public.vc_scores cascade;
drop table if exists public.vc_ai_summary_facts, public.vc_ai_summaries, public.vc_source_facts cascade;
drop function if exists public.vc_ai_check_approve() cascade;
drop function if exists public.vc_fact_mark_stale() cascade;
-- founded_year existed before these migrations; keep it.
alter table public.firms drop column if exists disambiguation,
  drop column if exists report_date, drop column if exists deleted_at;

-- merge-ready layer
drop schema if exists staging cascade;
drop table if exists public.vc_fact_conflicts, public.vc_aliases cascade;
alter table public.firms drop column if exists sec_crd, drop column if exists sec_file_no,
  drop column if exists legal_name, drop column if exists primary_domain;
do $$
declare t text;
begin
  foreach t in array array[
    'firms','funds','fund_entities','people','legal_matters','filings','docket_entries','regulatory_records',
    'sanctions_checks','press_items','sources','evidence_cards','takeaways','score_results','fact_events',
    'site_updates','site_stats','ui_strings'
  ] loop
    execute format('drop index if exists public.%I', t || '_origin_uq');
    execute format('alter table public.%I drop column if exists import_run_id, drop column if exists external_id, drop column if exists source_system', t);
  end loop;
end $$;
drop table if exists public.import_runs cascade;

-- data_status layer
drop function if exists public.purge_test_data(boolean);
drop function if exists public.promote_source(uuid, timestamptz);
alter table public.sources drop constraint if exists sources_real_needs_source,
  drop column if exists retrieved_at, drop column if exists needs_refetch;
alter table public.press_items drop constraint if exists press_real_needs_source,
  drop column if exists retrieved_at, drop column if exists needs_refetch;
do $$
declare t text;
begin
  foreach t in array array[
    'firms','funds','fund_entities','people','fund_people','investments','portfolio_companies','portfolio_metrics',
    'legal_matters','filings','docket_entries','regulatory_records','sanctions_checks','press_items','sources','fact_sources',
    'evidence_cards','evidence_lines','takeaways','ask_questions','copy_blocks','page_chips','list_items','firm_meta_items',
    'score_results','fact_events','site_updates','site_stats','ui_strings'
  ] loop
    execute format('alter table public.%I drop column if exists data_status', t);
  end loop;
end $$;
drop type if exists public.data_status;

do $$ begin
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    delete from supabase_migrations.schema_migrations where name in ('data_status', 'merge_ready', 'vc_profiles');
  end if;
end $$;
