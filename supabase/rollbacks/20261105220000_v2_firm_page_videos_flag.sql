-- Undo 20261105220000_v2_firm_page_videos_flag: drop the Videos section and hq_country from v2_firm_page.
do $m$
declare
  d text;
  n text;
  s int;
  e int;
begin
  if to_regprocedure('public.v2_firm_page(text)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;
  select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;
  n := replace(d,
    $q$'hq',hq,'hq_country',case when upper(btrim(f.hq_country)) ~ '^[A-Z]{2}$' then upper(btrim(f.hq_country)) end,'website'$q$,
    $q$'hq',hq,'website'$q$);
  s := position($q$  -- Videos: up to 3 current YouTube interviews$q$ in n);
  e := position($q$  -- G5/G6 What founders say:$q$ in n);
  if s = 0 or e = 0 or e < s then
    raise exception 'v2_firm_page: videos block not found';
  end if;
  n := left(n, s - 1) || substr(n, e);
  execute n;
end
$m$;
