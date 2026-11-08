-- Undo 20261108211827_v2_publish_social_accounts. Puts the social early return back.
-- Rows already published stay current. Nothing is deleted.
do $mig$
declare
  d text;
  n text;
  old text;
  new text;
begin
  if to_regprocedure('public.v2_publish_queue_item(bigint)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;
  select pg_get_functiondef('public.v2_publish_queue_item(bigint)'::regprocedure) into d;
  if position('F11.8 social' in d) > 0 then
    raise notice 'v2_publish_queue_item social early return already present';
    return;
  end if;
  old := $old$  IF q.table_name = 'v2_firms' THEN RETURN 'Confirmed: firm field already applied at submit (empty field filled)'; END IF;
$old$;
  new := $new$  IF q.table_name = 'v2_firms' THEN RETURN 'Confirmed: firm field already applied at submit (empty field filled)'; END IF;
  IF q.table_name = 'v2_social_accounts' THEN RETURN 'Confirmed: saved, not shown yet (F11.8 social)'; END IF;
$new$;
  if position(old in d) = 0 then
    raise exception 'v2_publish_queue_item: firms anchor missing';
  end if;
  n := replace(d, old, new);
  if n = d or position('F11.8 social' in n) = 0 then
    raise exception 'v2_publish_queue_item: social undo did not apply';
  end if;
  execute n;
end
$mig$;
