-- Turns the Checker off and puts the Enricher publish path back.
-- Does not delete page rows. Drops the new tables only when they are empty.

update bots.ingest_settings set value = 'false' where key = 'checker_publish';

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('checker-failure-retention');
  end if;
exception when others then
  null;
end $$;

drop trigger if exists investments_via_holding on public.investments;
drop trigger if exists reviews_via_holding on public.reviews;
drop function if exists public._investments_via_holding();
drop function if exists public._reviews_via_holding();

-- Previous trigger: only toxy-enricher calls promote_enrichment.
create or replace function public._enrichment_after_insert() returns trigger
language plpgsql security definer set search_path = bots, public as $$
begin
  if new.valid and new.bot_id = 'toxy-enricher' and new.firm_id is not null then
    perform promote_enrichment(new.firm_id);
  end if;
  if new.valid then
    perform search_log_from_enrichment(new.id);
    perform refresh_feedback_patterns();
  end if;
  return null;
end $$;

-- The previous research_enrich body is the function in
-- supabase/migrations/20261028010000_payload_notes.sql (rules text docs/DATA_RULES.md).
-- Re-apply that function from that file if the reply text must say DATA_RULES again.

drop function if exists public.checker_dry_run(text, jsonb);
drop function if exists public.checker_publish_firm(uuid, boolean, jsonb);
-- Part-source helpers from 20261028080000. Harmless if that migration was never applied.
drop function if exists public._checker_decide(uuid, text, jsonb, text, integer, jsonb);
drop function if exists public._names_firm(uuid, text);
drop function if exists public._known_outlet(text);
drop function if exists public._court_register(text);
drop function if exists public._host_is(text, text);
drop function if exists public._checker_write(uuid, text, jsonb, text, smallint, int);
drop function if exists public._checker_exists(uuid, text, jsonb, text);
drop function if exists public._checker_check_n(text, text);
drop function if exists public.checker_match_firm(text, text, text, text);
drop function if exists public._source_level(text, uuid, int);
drop function if exists public._checker_publish_on();
drop function if exists public.checker_purge_failures();

do $$
begin
  if (select count(*) from bots.checker_holding) = 0 then
    drop table bots.checker_holding;
  end if;
  if (select count(*) from public.checker_marks) = 0 then
    drop table public.checker_marks;
  end if;
end $$;
