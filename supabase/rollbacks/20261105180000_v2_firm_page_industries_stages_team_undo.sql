-- UNDO 20261105180000_v2_firm_page_industries_stages_team: officers, partners and board seats again; no industries or stages on the page.
do $m$
declare
  d text;
  n text;
  new_people text := $new$  -- E1: Team is the firm's CEO and founders only (live rows). No partners, officers, or board seats.
  select coalesce(jsonb_agg(q.p order by q.ord),'[]') into it from (
    select r.row_id ord, jsonb_build_object('head',pe.person_name,'kind','team','role',r.title,
        'is_founder',r.is_founder,'linkedin_url',nullif(btrim(pe.linkedin_url),''),'x_url',nullif(btrim(pe.x_url),'')) p
      from (
        select distinct on (person_id) *
          from v2_person_firm_roles
         where firm_id=fid and is_current and not archived and not nothing_found
           and (is_founder or coalesce(title,'') ~* '(\mCEO\M|chief executive officer)')
         order by person_id, is_founder desc, row_id
      ) r
      join v2_people pe on pe.person_id=r.person_id
     where pe.is_current and not pe.archived and not pe.nothing_found
  ) q;
  if jsonb_array_length(it)>0 then secs := secs || jsonb_build_object('key','people','title','Team','subtitle','','renderer','people','count',jsonb_array_length(it),'unit',case when jsonb_array_length(it)=1 then 'person' else 'people' end,'teaser',it->0->>'head','items',it); end if;$new$;
  old_people text := $old$  -- people: officers + board seats merged per person
  select coalesce(jsonb_agg(p order by ord, p->>'head'),'[]') into it from (
    select 0 ord, jsonb_build_object('head',pe.person_name,'kind','officer','role',r.title,'src',_v2_src(r.source_url,r.source_date,r.source_type)) p
      from v2_person_firm_roles r join v2_people pe on pe.person_id=r.person_id
     where r.firm_id=fid and r.kind='officer' and r.is_current and not r.archived
    union all
    select case when r.is_founder then 1 when r.joined_year is not null then 2 + (9999 - r.joined_year) / 10000.0 else 3 end,
        jsonb_build_object('head',pe.person_name,'kind','partner','role',r.title,'joined_year',r.joined_year,'left_year',r.left_year,
          'badge',case when r.is_founder then 'Founder' end,'src',_v2_src(r.source_url,r.source_date,r.source_type))
      from v2_person_firm_roles r join v2_people pe on pe.person_id=r.person_id
     where r.firm_id=fid and r.kind='partner' and r.is_current and not r.archived
       and (r.left_year is null or r.left_year >= extract(year from now())::int - 1)
    union all
    select 4, jsonb_build_object('head',pe.person_name,'kind','board',
        'role',case when count(distinct s.startup_name)=1 then 'Board seat: ' else 'Board seats: ' end||string_agg(distinct s.startup_name,', '),
        'src',(select coalesce(jsonb_agg(x),'[]') from (select distinct on (b2.source_url) _v2_src(b2.source_url,b2.source_date,b2.source_type)->0 x from v2_board_seats b2 where b2.person_id=pe.person_id and b2.is_current and not b2.archived limit 3) z))
      from v2_board_seats b join v2_people pe on pe.person_id=b.person_id left join v2_startups s on s.startup_id=b.startup_id
     where b.is_current and not b.archived and exists (select 1 from v2_person_firm_roles r where r.person_id=b.person_id and r.firm_id=fid)
     group by pe.person_id, pe.person_name) q;
  if jsonb_array_length(it)>0 then secs := secs || jsonb_build_object('key','people','title','People & board seats','subtitle','Officers, partner moves and board seats.','renderer','people','count',jsonb_array_length(it),'unit',case when jsonb_array_length(it)=1 then 'person' else 'people' end,'teaser',it->0->>'head','items',it); end if;$old$;
  new_year text := $y$'founded_year',f.founded_year,
       'industries',coalesce((select json_agg(i.industry_text order by i.position, i.id) from v2_firm_industries i where i.firm_id=fid and not i.archived),'[]'::json),
       'stages',coalesce((select json_agg(s.stage order by case lower(btrim(s.stage)) when 'pre-seed' then 1 when 'seed' then 2 when 'series a' then 3 when 'series b' then 4 when 'series c and later' then 5 when 'growth' then 6 else 7 end, s.id) from v2_firm_stages s where s.firm_id=fid),'[]'::json),$y$;
  old_year text := $y$'founded_year',f.founded_year,$y$;
begin
  if to_regprocedure('public.v2_firm_page(text)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;
  select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;
  if position(new_people in d) = 0 or position(new_year in d) = 0 then
    raise exception 'v2_firm_page: team patch not found';
  end if;
  n := replace(replace(d, new_people, old_people), new_year, old_year);
  if n = d then raise exception 'v2_firm_page: undo did not apply'; end if;
  execute n;
end $m$;
