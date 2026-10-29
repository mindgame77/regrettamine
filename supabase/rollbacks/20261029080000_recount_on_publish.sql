-- Rollback for 20261029080000_recount_on_publish.sql
drop trigger if exists zz_checks_recount_on_publish on public.publish_checks;
drop function if exists public._checks_recount_on_publish();
drop function if exists public.refresh_firm_check_results(uuid);
drop function if exists public._checks_on();
create or replace function public.refresh_firm_check_pills(p_firm uuid)
 returns void language plpgsql security definer set search_path = public as $$ begin return; end $$;
revoke all on function public.refresh_firm_check_pills(uuid) from public, anon, authenticated;
do $$ begin
  if to_regclass('public.firm_check_results') is not null and to_regclass('public.firm_check_pills') is null then
    alter table public.firm_check_results rename to firm_check_pills;
    alter table public.firm_check_pills rename constraint firm_check_results_pkey to firm_check_pills_pkey;
    alter table public.firm_check_pills rename constraint firm_check_results_firm_id_fkey to firm_check_pills_firm_id_fkey;
  end if;
end $$;
