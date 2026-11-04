-- E2.1/E2.2/E4.2: firm page people include kind=partner rows with joined_year/left_year
do $m$ declare d text; n text; begin
  select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;
  n := replace(replace(d, $q$'kind','officer','role',r.title,'src',$q$, $q$'kind','officer','role',r.title,'joined_year',r.joined_year,'left_year',r.left_year,'src',$q$), $q$r.kind='officer' and r.is_current$q$, $q$r.kind in ('officer','partner') and r.is_current$q$);
  if n = d then raise exception 'v2_firm_page: expected text not found'; end if;
  execute n;
end $m$;
