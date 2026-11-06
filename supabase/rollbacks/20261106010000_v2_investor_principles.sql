-- Undo 20261106010000_v2_investor_principles: drop the section from v2_firm_page and drop the table.
do $mig$
declare
  d text;
  n text;
  s int;
  e int;
  mark text := '  -- end What investors look for';
begin
  if to_regprocedure('public.v2_firm_page(text)') is not null then
    select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;
    s := position('  -- What investors look for:' in d);
    e := position(mark in d);
    if s = 0 or e = 0 or e < s then
      raise notice 'v2_firm_page: investors block not found';
    else
      e := e + length(mark);
      if substr(d, e + 1, 1) = chr(10) then e := e + 1; end if;
      n := left(d, s - 1) || substr(d, e + 1);
      if position('  -- What investors look for:' in n) > 0 then
        raise exception 'v2_firm_page: investors undo did not apply';
      end if;
      execute n;
    end if;
  end if;
  if to_regclass('public.v2_investor_principles') is not null then
    execute 'drop table public.v2_investor_principles';
  end if;
end
$mig$;
