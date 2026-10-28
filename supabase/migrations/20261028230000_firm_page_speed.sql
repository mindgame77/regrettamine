-- Page-speed probe for the 10 lab firms. Runs firm_page inside a subtransaction that is always
-- rolled back, so no unlock, visit, or spend is recorded. Returns server-side milliseconds.
create or replace function public.firm_page_speed(p_slug text)
returns integer language plpgsql volatile security definer set search_path to 'public' as $function$
declare
  v_firm uuid;
  t0 timestamptz;
  ms integer;
begin
  select id into v_firm from public.firms where slug = p_slug;
  if v_firm is null or not public._lab_firm(v_firm) then
    raise exception 'firm_page_speed: lab firms only';
  end if;
  begin
    t0 := clock_timestamp();
    perform public.firm_page(p_slug, '00000000-0000-4000-8000-00000000abcd'::uuid, false, null);
    ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
    raise exception using errcode = 'P0001', message = 'zz_rollback';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'zz_rollback' then raise; end if;
  end;
  return ms;
end $function$;
revoke all on function public.firm_page_speed(text) from public;
grant execute on function public.firm_page_speed(text) to anon, authenticated;
