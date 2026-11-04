-- The v2 schema is not created by repo migrations; on a database without v2_reviews (CI) this is a no-op.
-- Applied to production via Supabase as v2_reviews_reviewer_role (20261104200909).
do $mig$
begin
  if to_regclass('public.v2_reviews') is null then raise notice 'v2 schema missing, skipped'; return; end if;
  execute $mx$
alter table public.v2_reviews
  add column if not exists reviewer_role varchar(120),
  add column if not exists reviewer_company varchar(160),
  add column if not exists reviewer_role_source_url text;
comment on column public.v2_reviews.reviewer_role is 'G5: reviewer role, only when confirmed by reviewer_role_source_url';
comment on column public.v2_reviews.reviewer_company is 'G5: reviewer company, only when confirmed by reviewer_role_source_url';
update public.v2_reviews set review_author='Irem Sumer', reviewer_role='CEO', reviewer_company='Talemonster Games', reviewer_role_source_url='https://www.businessinsider.com/talemonster-games-startup-match-valley-a16z-30-million-series-a-2026-1' where row_id=12;
update public.v2_reviews set reviewer_role='CEO', reviewer_company='ChartHop', reviewer_role_source_url='https://www.alleywatch.com/2020/09/charthop-organization-management-platform-chart-ian-white/' where row_id=13;
update public.v2_reviews set reviewer_role='CEO', reviewer_company='Pylon', reviewer_role_source_url='https://linkedin.com/in/martykausas' where row_id=14;
update public.v2_reviews set reviewer_role='CEO', reviewer_company='Ketone', reviewer_role_source_url='https://x.com/MichaelDBrandt' where row_id=15;
update public.v2_reviews set reviewer_role=null, reviewer_company='Keybase', reviewer_role_source_url='https://news.ycombinator.com/item?id=19563592' where row_id=19;
update public.v2_reviews set reviewer_role='Founder', reviewer_company='Wit.ai', reviewer_role_source_url='https://news.ycombinator.com/user?id=ar7hur' where row_id=20;
CREATE OR REPLACE FUNCTION public.v2_firm_page(p_slug text)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f v2_firms; fid bigint; deals jsonb; d12 jsonb; funds jsonb; lf jsonb; aum v2_firm_aum; secs jsonb := '[]'; it jsonb; hq text; ct v2_firm_contacts; sp jsonb; fa jsonb; fal jsonb; revs jsonb;
begin
  fid := _v2_live_id(p_slug);
  if fid is null then return json_build_object('status','not_found'); end if;
  select * into f from v2_firms where firm_id=fid;
  hq := nullif(concat_ws(', ', f.hq_city, coalesce(f.hq_state, f.hq_country)),'');
  -- G1.1 header pills: newest current, non-archived contact row (Checker-passed = is_current)
  select * into ct from v2_firm_contacts where firm_id=fid and is_current and not archived and not nothing_found
   order by source_date desc nulls last, row_id desc limit 1;
  -- G1.1: SEC Form ADV Staff / Investment staff counts (Private funds left out, per approved mockup)
  select coalesce(jsonb_agg(jsonb_build_object('label',x.fact_label,'value',x.fact_value::text,'anchor','overview',
      'src',_v2_src(x.source_url,x.source_date,x.source_type)) order by case x.fact_label when 'Staff' then 0 else 1 end),'[]') into sp
    from (select distinct on (fact_label) * from v2_sec_fact_pills
           where firm_id=fid and is_current and not archived and not nothing_found and fact_value>0
             and fact_label in ('Staff','Investment staff')
           order by fact_label, source_date desc nulls last, row_id desc) x;
  deals := _v2_deals(fid);
  select coalesce(jsonb_agg(e),'[]') into d12 from jsonb_array_elements(deals) e where e->>'date' >= (current_date - 365)::text;
  select coalesce(jsonb_agg(jsonb_build_object('name',fund_name,'raised_usd',case when amount_currency='USD' then amount_raised end,'date',closed_on::text,'url',source_url) order by coalesce(closed_on,source_date) desc nulls last, fund_name),'[]')
    into funds from v2_funds where firm_id=fid and is_current and not archived and not nothing_found;
  select jsonb_build_object('name',fund_name,'raised_usd',amount_raised,'url',source_url,'date',closed_on::text) into lf
    from v2_funds where firm_id=fid and is_current and not archived and closed_on is not null and amount_raised is not null and amount_currency='USD' order by closed_on desc limit 1;
  -- Announced funds: the firm's own fund announcement (not Form D; kept out of v2_funds). Newest first, biggest first.
  select coalesce(jsonb_agg(jsonb_build_object('name',a.name,'raised_usd',a.amount_usd,'raised_display',a.display,'date',a.announced_on::text,'url',a.url)
           order by a.announced_on desc, a.amount_usd desc, a.name),'[]') into fa
    from firm_fund_announcements a where a.firm_id=fid;
  -- Latest announcement (one date + url) as one total for the Latest fund tile.
  select jsonb_build_object('n',count(*),'total_usd',sum(a.amount_usd),'total_display',public._money_display(sum(a.amount_usd),'USD'),
           'date',max(a.announced_on)::text,'url',max(a.url)) into fal
    from firm_fund_announcements a
   where a.firm_id=fid and (a.announced_on,a.url)=(select b.announced_on,b.url from firm_fund_announcements b where b.firm_id=fid order by b.announced_on desc,b.url limit 1)
  having count(*)>0;
  select * into aum from v2_firm_aum where firm_id=fid and is_current and not archived and not nothing_found order by source_date desc nulls last limit 1;
  -- overview / thesis (F12.8): first section, no source or pill; no thesis = no section
  if nullif(trim(coalesce(f.thesis_text,'')),'') is not null then
    secs := secs || jsonb_build_object('key','overview','items',jsonb_build_array(jsonb_build_object('label','thesis','value',trim(f.thesis_text))));
  end if;
  -- legal
  select coalesce(jsonb_agg(jsonb_build_object('grp',l.item_group,'head',coalesce(l.other_party,l.regulator_name)||' v. '||f.display_name,
      'note',concat_ws('. ',nullif(l.court,''),null),'role',l.side,'tone',null,'year',l.filed_year::text,'state',l.status,
      'status',case when l.closed_year is not null then l.status||' '||l.closed_year end,'summary',l.case_summary,'summary_url',l.summary_source_url,'summary_date',l.summary_date::text,
      'src',_v2_src(l.source_url,l.source_date,'CourtListener')) order by l.filed_year desc nulls last),'[]') into it
    from v2_legal_items l where l.firm_id=fid and l.is_current and not l.archived and not l.nothing_found and not coalesce(l.lead_only,false);
  if jsonb_array_length(it)>0 then secs := secs || jsonb_build_object('key','legal','title','Legal & regulatory','subtitle','Cases where the firm itself is a party, and regulator records.','renderer','legal','count',jsonb_array_length(it),'unit',case when jsonb_array_length(it)=1 then 'record' else 'records' end,'teaser',it->0->>'head','items',it); end if;
  -- press
  select coalesce(jsonb_agg(jsonb_build_object('url',n.source_url,'date',to_char(n.published_date,'Mon FMDD, YYYY'),'head',n.headline,'outlet',n.outlet,
      'src',_v2_src(n.source_url,n.published_date,n.outlet)) order by n.published_date desc nulls last),'[]') into it
    from v2_news_items n where n.firm_id=fid and n.is_current and not n.archived and not n.nothing_found and n.headline is not null;
  if jsonb_array_length(it)>0 then secs := secs || jsonb_build_object('key','press','title','Press coverage','subtitle','Articles naming the firm, with the outlet and date.','renderer','press','count',jsonb_array_length(it),'unit',case when jsonb_array_length(it)=1 then 'article' else 'articles' end,'teaser',it->0->>'head','items',it); end if;
  -- LPs (M4.8): only Checker-passed rows (is_current) that are not archived. One item per commitment;
  -- company.js groupLps draws one line per LP name. At most 100 LP names (M4.8.2), biggest total first.
  -- No LPs = no section (M4.8.3).
  select coalesce(jsonb_agg(jsonb_build_object('label',c.lp_name,
      'value',case when c.commitment_amount>0 and coalesce(c.commitment_currency,'USD')='USD' then
        case when c.commitment_amount>=1e9 then '$'||trim(trailing '.' from trim(trailing '0' from to_char(c.commitment_amount/1e9,'FM999990.0')))||'B'
             else '$'||trim(trailing '.' from trim(trailing '0' from to_char(c.commitment_amount/1e6,'FM999990.0')))||'M' end
        when c.commitment_amount>0 then trim(to_char(c.commitment_amount,'FM999999999999990'))||' '||c.commitment_currency else '' end,
      'type',c.lp_type,'fund',fu.fund_name,'year',c.commitment_year,
      'src',_v2_src(c.source_url,c.source_date,c.source_type)) order by t.rk, c.commitment_amount desc nulls last, c.row_id),'[]') into it
    from v2_lp_commitments c
    join (select lower(trim(lp_name)) k, row_number() over (order by sum(coalesce(commitment_amount,0)) desc, lower(trim(lp_name))) rk
            from v2_lp_commitments where firm_id=fid and is_current and not archived and not nothing_found group by 1) t on t.k=lower(trim(c.lp_name)) and t.rk<=100
    left join v2_funds fu on fu.fund_id=c.fund_id
   where c.firm_id=fid and c.is_current and not c.archived and not c.nothing_found;
  if jsonb_array_length(it)>0 then
    secs := secs || jsonb_build_object('key','lps','title','Limited partners','subtitle','Named LP commitments, each with its source.','renderer','facts',
      'count',(select count(distinct lower(trim(e->>'label'))) from jsonb_array_elements(it) e),
      'unit',case when (select count(distinct lower(trim(e->>'label'))) from jsonb_array_elements(it) e)=1 then 'LP' else 'LPs' end,'teaser',it->0->>'label','items',it);
  end if;
  -- people: officers + board seats merged per person
  select coalesce(jsonb_agg(p order by ord, p->>'head'),'[]') into it from (
    select 0 ord, jsonb_build_object('head',pe.person_name,'kind','officer','role',r.title,'src',_v2_src(r.source_url,r.source_date,r.source_type)) p
      from v2_person_firm_roles r join v2_people pe on pe.person_id=r.person_id
     where r.firm_id=fid and r.kind='officer' and r.is_current and not r.archived
    union all
    select 1, jsonb_build_object('head',pe.person_name,'kind','board',
        'role',case when count(distinct s.startup_name)=1 then 'Board seat: ' else 'Board seats: ' end||string_agg(distinct s.startup_name,', '),
        'src',(select coalesce(jsonb_agg(x),'[]') from (select distinct on (b2.source_url) _v2_src(b2.source_url,b2.source_date,b2.source_type)->0 x from v2_board_seats b2 where b2.person_id=pe.person_id and b2.is_current and not b2.archived limit 3) z))
      from v2_board_seats b join v2_people pe on pe.person_id=b.person_id left join v2_startups s on s.startup_id=b.startup_id
     where b.is_current and not b.archived and exists (select 1 from v2_person_firm_roles r where r.person_id=b.person_id and r.firm_id=fid)
     group by pe.person_id, pe.person_name) q;
  if jsonb_array_length(it)>0 then secs := secs || jsonb_build_object('key','people','title','People & board seats','subtitle','Officers, partner moves and board seats.','renderer','people','count',jsonb_array_length(it),'unit',case when jsonb_array_length(it)=1 then 'person' else 'people' end,'teaser',it->0->>'head','items',it); end if;
  -- G5/G6 What founders say: only Checker-passed (is_current), not archived review rows, newest first.
  select coalesce(jsonb_agg(jsonb_build_object('summary',nullif(trim(r.summary),''),'body',nullif(trim(r.quote),''),'quote',nullif(trim(r.quote),''),
      'author',r.review_author,'name',r.review_author,'role',nullif(r.reviewer_role,''),'company',nullif(r.reviewer_company,''),
      'year',r.review_year,'date',coalesce(r.source_date::text,r.review_year::text),
      'url',r.source_url,'site',r.review_source_name,'outlet',r.review_source_name,'source_type',r.source_type,'tone',r.tone,
      'src',_v2_src(r.source_url,r.source_date,coalesce(r.review_source_name,r.source_type)))
      order by coalesce(r.source_date,make_date(r.review_year::int,1,1)) desc nulls last, r.row_id desc),'[]') into revs
    from v2_reviews r where r.firm_id=fid and r.is_current and not r.archived and not coalesce(r.nothing_found,false);
  return json_build_object('status','ok','open',true,'unchecked',false,'done',null,'source','v2',
    'firm',json_build_object('slug',f.slug,'name',f.display_name,'sec_name',coalesce(f.legal_name,f.display_name),'short_name',f.short_name,'hq',hq,'website',f.website_url,'assets',null,
       'social','[]'::json,'founded_year',f.founded_year,
       'contact_email',nullif(trim(ct.contact_email),''),'contact_phone',nullif(trim(ct.contact_phone),''),'apply_link',nullif(trim(ct.apply_link),''),
       'money',case when aum.row_id is not null then json_build_object('aum',json_build_object('display',case when aum.aum_amount>=1e9 then '$'||trim(trailing '.' from trim(trailing '0' from to_char(aum.aum_amount/1e9,'FM999990.0')))||'B' else '$'||trim(trailing '.' from trim(trailing '0' from to_char(aum.aum_amount/1e6,'FM999990.0')))||'M' end,'url',aum.source_url,'date',aum.source_date::text,'source_label','SEC Form ADV')) else '{}'::json end),
    'hero',(case when hq is not null then jsonb_build_array(jsonb_build_object('label','HQ','value',hq,'anchor','overview','src',_v2_src(f.hq_source->>'url',(f.hq_source->>'date')::date,'SEC IAPD'))) else '[]'::jsonb end) || sp,
    'sections',secs,'checks','[]'::json,'queue',null,'started_at',null,'details','[]'::json,'outline',null,'ondemand',null,
    'activity',json_build_object('lazy',false,'active',true,'deals',deals,'reviews',revs,'latest_deal',deals->0,'latest_review',revs->0,'latest_fund',lf,
       'counts',json_build_object('deals',jsonb_array_length(deals),'reviews',jsonb_array_length(revs)),'deals_12m',jsonb_array_length(d12),
       'sector_12m',(select json_build_object('n',jsonb_array_length(d12),'top',coalesce((select json_agg(json_build_object('s',s,'n',n) order by n desc,s) from (select e->>'sector' s,count(*) n from jsonb_array_elements(d12) e where e->>'sector' is not null group by 1 order by 2 desc limit 10) t),'[]'),
          'other',jsonb_array_length(d12)-coalesce((select sum(n) from (select count(*) n from jsonb_array_elements(d12) e where e->>'sector' is not null group by e->>'sector' order by 1 desc limit 10) t),0))),
       'funds_announced',json_build_object('n',jsonb_array_length(fa),'latest',fal,'items',fa),
       'funds_sec',json_build_object('n',jsonb_array_length(funds),'items',funds),'funds_closed_12m',(select count(*) from jsonb_array_elements(funds) e where e->>'date' >= (current_date-365)::text)));
end $function$;

$mx$;
end
$mig$;
