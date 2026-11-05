-- UNDO 20261104235000_v2_firm_page_partner_years: back to officers + board only.
do $m$ declare d text; n text; s int; e int; begin
  select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;
  s := position($q$    select case when r.is_founder then 1$q$ in d);
  e := position($q$and (r.left_year is null or r.left_year >= extract(year from now())::int - 1)
    union all
$q$ in d);
  if s = 0 or e = 0 then raise exception 'v2_firm_page: expected text not found'; end if;
  n := left(d, s - 1) || substr(d, e + length($q$and (r.left_year is null or r.left_year >= extract(year from now())::int - 1)
    union all
$q$));
  n := replace(n, $q$select 4, jsonb_build_object('head',pe.person_name,'kind','board',$q$, $q$select 1, jsonb_build_object('head',pe.person_name,'kind','board',$q$);
  execute n;
end $m$;
