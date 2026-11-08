-- Undo 20261108200000_v2_firm_page_check_size: drop firm.check_size from v2_firm_page.
-- Rows in v2_firm_check_sizes stay. Nothing is deleted.
do $mig$
declare
  d text;
  n text;
  old text;
begin
  if to_regprocedure('public.v2_firm_page(text)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;
  select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;
  old := $old$'check_size',(select nullif(btrim(c.amount_text),'') from v2_firm_check_sizes c where c.firm_id=fid and c.is_current and not c.archived and nullif(btrim(c.amount_text),'') is not null order by c.read_on desc nulls last, c.id desc limit 1),
       $old$;
  if position(old in d) = 0 then
    raise notice 'v2_firm_page check size already absent';
    return;
  end if;
  n := replace(d, old, '');
  if n = d or position('from v2_firm_check_sizes c' in n) > 0 then
    raise exception 'v2_firm_page: check size undo did not apply';
  end if;
  execute n;
end
$mig$;
