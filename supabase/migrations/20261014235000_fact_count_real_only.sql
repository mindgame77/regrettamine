-- Public record count only counts real rows. New events default to data_status 'test'
-- (research imports land as test), so imports don't inflate the landing number until promoted.
create or replace function public.fact_record_count()
returns bigint language sql stable security definer set search_path = public as $$
  select count(*) from public.fact_events where data_status = 'real';
$$;
