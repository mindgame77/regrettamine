-- E2.1/E2.2/E4.2: firm page people include current partner rows (kind=partner) with joined_year/left_year/is_founder.
-- Order (provisional): officers, then founders of the firm, then partners with a joined_year newest first, then the rest A-Z; board last (never shown, E3).
-- Rows that left more than ~12 months ago are not sent (former, E4.1/E4.2) even if is_current.
do $m$ declare d text; n text; begin
  select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;
  n := replace(d, $q$select 1, jsonb_build_object('head',pe.person_name,'kind','board',$q$, $q$select 4, jsonb_build_object('head',pe.person_name,'kind','board',$q$);
  n := replace(n, $q$where r.firm_id=fid and r.kind='officer' and r.is_current and not r.archived
    union all$q$, $q$where r.firm_id=fid and r.kind='officer' and r.is_current and not r.archived
    union all
    select case when r.is_founder then 1 when r.joined_year is not null then 2 + (9999 - r.joined_year) / 10000.0 else 3 end,
        jsonb_build_object('head',pe.person_name,'kind','partner','role',r.title,'joined_year',r.joined_year,'left_year',r.left_year,
          'badge',case when r.is_founder then 'Founder' end,'src',_v2_src(r.source_url,r.source_date,r.source_type))
      from v2_person_firm_roles r join v2_people pe on pe.person_id=r.person_id
     where r.firm_id=fid and r.kind='partner' and r.is_current and not r.archived
       and (r.left_year is null or r.left_year >= extract(year from now())::int - 1)
    union all$q$);
  if n = d or position('''kind'',''partner''' in n) = 0 or position('select 4, jsonb_build_object' in n) = 0 then raise exception 'v2_firm_page: expected text not found'; end if;
  execute n;
end $m$;
