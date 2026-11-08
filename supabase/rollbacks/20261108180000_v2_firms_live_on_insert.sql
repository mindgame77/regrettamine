-- Undo live-on-insert. Drops the trigger and function only.
-- Rows already in v2_firm_live stay. public.firms is not read or written. Nothing is deleted.
do $mig$
begin
  if to_regclass('public.v2_firms') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;
  execute 'drop trigger if exists v2_firms_live_on_insert on public.v2_firms';
  execute 'drop function if exists public.v2_firm_live_on_insert()';
end
$mig$;
