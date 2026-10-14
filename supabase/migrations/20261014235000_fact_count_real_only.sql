-- Public record count excludes rows that came in through a research import until they are promoted.
-- Import loaders tag their fact_events with import_run_id; seed/repo rows have none and still count.
create or replace function public.fact_record_count()
returns bigint language sql stable security definer set search_path = public as $$
  select count(*) from public.fact_events where import_run_id is null or data_status = 'real';
$$;
