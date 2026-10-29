-- Step C (Alex, 2026-10-28): when the Checker publishes an item, refresh that firm's saved check counts
-- so the firm page and My firms update. firm_check_pills (empty, 0 rows) is renamed firm_check_results.
-- The 10 checks stay OFF: the recount only runs when bots.ingest_settings 'checks_on' = 'true', which is not set.
-- Rollback: supabase/rollbacks/20261029080000_recount_on_publish.sql

do $$ begin
  if to_regclass('public.firm_check_pills') is not null then
    if exists (select 1 from public.firm_check_pills) then
      raise exception 'firm_check_pills is not empty; not renaming';
    end if;
    alter table public.firm_check_pills rename to firm_check_results;
    alter table public.firm_check_results rename constraint firm_check_pills_pkey to firm_check_results_pkey;
    alter table public.firm_check_results rename constraint firm_check_pills_firm_id_fkey to firm_check_results_firm_id_fkey;
  end if;
end $$;

create or replace function public._checks_on()
 returns boolean language sql stable security definer set search_path = bots, public as $$
  select coalesce((select value from bots.ingest_settings where key = 'checks_on'), 'false') = 'true';
$$;

-- Recounts one firm's 10 checks and saves them (A8.1). No-op while the checks are off.
create or replace function public.refresh_firm_check_results(p_firm uuid)
 returns boolean language plpgsql security definer set search_path = public as $$
begin
  if p_firm is null or not public._checks_on() then return false; end if;
  insert into public.firm_check_results (firm_id, checks, computed_at)
  values (p_firm, public._firm_checks_compute(p_firm), now())
  on conflict (firm_id) do update set checks = excluded.checks, computed_at = excluded.computed_at;
  delete from public.firm_page_cache where firm_id = p_firm;  -- firm page and My firms rebuild from the saved counts
  return true;
end $$;

drop function if exists public.refresh_firm_check_pills(uuid);

-- After the Checker publishes (or merges) items, recount each firm it touched once.
create or replace function public._checks_recount_on_publish()
 returns trigger language plpgsql security definer set search_path = public as $$
declare fid uuid;
begin
  if not public._checks_on() then return null; end if;
  for fid in select distinct n.firm_id from new_rows n
              where n.bot_id = 'checker' and n.outcome in ('published', 'merged') and n.firm_id is not null loop
    perform public.refresh_firm_check_results(fid);
  end loop;
  return null;
end $$;

drop trigger if exists zz_checks_recount_on_publish on public.publish_checks;
create trigger zz_checks_recount_on_publish after insert on public.publish_checks
  referencing new table as new_rows for each statement execute function public._checks_recount_on_publish();

revoke all on function public._checks_on() from public, anon, authenticated;
revoke all on function public.refresh_firm_check_results(uuid) from public, anon, authenticated;
revoke all on function public._checks_recount_on_publish() from public, anon, authenticated;
grant execute on function public.refresh_firm_check_results(uuid) to service_role;
