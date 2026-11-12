-- One stored copy of public.firm_directory(). Rebuilt every hour.
-- The Investors page reads firm_directory_cached(). firm_directory() is unchanged.
-- Apply this file when the cache should go live. It is not applied by the pull request.

create table public.v2_firm_directory_cache (
  id int primary key default 1 check (id = 1),
  payload jsonb not null,
  built_at timestamptz not null
);

alter table public.v2_firm_directory_cache enable row level security;
revoke all on table public.v2_firm_directory_cache from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant select, insert, update, delete on table public.v2_firm_directory_cache to service_role';
  end if;
end $$;

comment on table public.v2_firm_directory_cache is
  'Single row (id = 1) of the firm_directory() JSON array. Anon reads it through firm_directory_cached(), not this table.';

-- 60s applies only while this function runs. The anon role keeps its own short timeout.
-- Cron (and service_role) call it. Visitors do not.
create or replace function public.refresh_firm_directory_cache()
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
set statement_timeout to '60s'
as $$
begin
  if to_regprocedure('public.firm_directory()') is null then
    return;
  end if;
  insert into public.v2_firm_directory_cache (id, payload, built_at)
  values (1, coalesce(public.firm_directory()::jsonb, '[]'::jsonb), now())
  on conflict (id) do update
    set payload = excluded.payload,
        built_at = excluded.built_at;
end
$$;

revoke all on function public.refresh_firm_directory_cache() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.refresh_firm_directory_cache() to service_role';
  end if;
end $$;

create or replace function public.firm_directory_cached()
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select jsonb_build_object('payload', c.payload, 'built_at', c.built_at)
    from public.v2_firm_directory_cache c
   where c.id = 1
$$;

revoke all on function public.firm_directory_cached() from public, anon, authenticated;
grant execute on function public.firm_directory_cached() to anon, authenticated;

-- Hourly. Skipped where pg_cron is not installed (local tests, CI).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'firm-directory-cache') then
      perform cron.unschedule('firm-directory-cache');
    end if;
    perform cron.schedule(
      'firm-directory-cache',
      '0 * * * *',
      'select public.refresh_firm_directory_cache()'
    );
  else
    raise notice 'pg_cron is not installed; firm-directory-cache is not scheduled';
  end if;
end $$;

select public.refresh_firm_directory_cache();
