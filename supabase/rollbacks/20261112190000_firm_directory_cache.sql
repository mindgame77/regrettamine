-- Removes the firm directory cache, its two functions, and the hourly job.
-- Does not change or drop public.firm_directory().

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'firm-directory-cache') then
      perform cron.unschedule('firm-directory-cache');
    end if;
  end if;
end $$;

drop function if exists public.firm_directory_cached();
drop function if exists public.refresh_firm_directory_cache();
drop table if exists public.v2_firm_directory_cache;
