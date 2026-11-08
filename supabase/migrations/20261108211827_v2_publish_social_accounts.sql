-- A passed social account publishes like every other item table: is_current becomes true.
-- v2_firm_page already returns those current rows. This removes only the early return
-- that stopped the update. Firms, deals, fund assets, and the archived path stay as they are.
-- No rows change here. Accel's three approved rows are supabase/replay/20261108211827_accel_approved_social.sql,
-- run only after this migration is applied and the owner says yes.
-- A database without v2_publish_queue_item (CI) skips this.
do $mig$
declare
  d text;
  n text;
  old text;
begin
  if to_regprocedure('public.v2_publish_queue_item(bigint)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;

  select pg_get_functiondef('public.v2_publish_queue_item(bigint)'::regprocedure) into d;
  old := $old$  IF q.table_name = 'v2_social_accounts' THEN RETURN 'Confirmed: saved, not shown yet (F11.8 social)'; END IF;
$old$;
  if position(old in d) > 0 then
    n := replace(d, old, '');
    if n = d
       or position('F11.8 social' in n) > 0
       or position($f$IF q.table_name = 'v2_firms'$f$ in n) = 0
       or position($f$IF q.table_name = 'v2_deals'$f$ in n) = 0
       or position('SET is_current = true' in n) = 0
       or position('M3.8 fund assets' in n) > 0 then
      raise exception 'v2_publish_queue_item: social patch did not apply';
    end if;
    execute n;
  elsif position('F11.8 social' in d) > 0 then
    raise exception 'v2_publish_queue_item: social no-op anchor missing';
  end if;
end
$mig$;
