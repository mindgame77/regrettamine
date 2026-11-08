-- Team = founders plus whoever runs the firm today (CEO, co-steward, managing partner).
-- A reputable dated news source (level 3, source_type News) may back a current-leader role. Nobody else.
create or replace function public.v2_is_leader_title(t text) returns boolean
  language sql immutable set search_path to 'public' as
$$ select coalesce(t,'') ~* '(\mCEO\M|chief executive officer|\msteward\M|managing partner)' $$;

alter table public.v2_person_firm_roles drop constraint if exists v2_pfr_ceo_or_founder;
alter table public.v2_person_firm_roles add constraint v2_pfr_ceo_or_founder
  check (archived or nothing_found or is_founder or v2_is_leader_title(title));

alter table public.v2_person_firm_roles drop constraint if exists v2_person_firm_roles_source_level_check1;
alter table public.v2_person_firm_roles add constraint v2_person_firm_roles_source_level_check1
  check (source_level in (1,2) or (source_level = 3 and source_type = 'News' and v2_is_leader_title(title)));

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
  -- G1.1: Private funds count only. Staff and Investment staff are not published
  select coalesce(jsonb_agg(jsonb_build_object('label',x.fact_label,'value',x.fact_value::text,'anchor','overview',
      'src',_v2_src(x.source_url,x.source_date,x.source_type)) order by case x.fact_label when 'Staff' then 0 else 1 end),'[]') into sp
    from (select distinct on (fact_label) * from v2_sec_fact_pills
           where firm_id=fid and is_current and not archived and not nothing_found and fact_value>0
             and fact_label in ('Private funds')
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
    from firm_fund_announcements a where a.firm_id=fid and a.is_current and not a.archived;
  -- Latest announcement (one date + url) as one total for the Latest fund tile.
  select jsonb_build_object('n',count(*),'total_usd',sum(a.amount_usd),'total_display',public._money_display(sum(a.amount_usd),'USD'),
           'date',max(a.announced_on)::text,'url',max(a.url)) into fal
    from firm_fund_announcements a
   where a.firm_id=fid and a.is_current and not a.archived and (a.announced_on,a.url)=(select b.announced_on,b.url from firm_fund_announcements b where b.firm_id=fid and b.is_current and not b.archived order by b.announced_on desc,b.url limit 1)
  having count(*)>0;
  select * into aum from v2_firm_aum where firm_id=fid and is_current and not archived and not nothing_found order by source_date desc nulls last limit 1;
  -- overview / thesis (F12.8): first section, no source or pill; no thesis = no section
  if nullif(trim(coalesce(f.thesis_text,'')),'') is not null then
    secs := secs || jsonb_build_object('key','overview','items',jsonb_build_array(jsonb_build_object('label','thesis','value',trim(f.thesis_text))));
  end if;
  -- What investors look for: sourced rows only. None = no section.
  select coalesce(jsonb_agg(jsonb_build_object(
      'investor_name',p.investor_name,'investor_title',p.investor_title,
      'summary',p.summary,'quote',p.quote,'published_at',p.published_at::text,'source_url',p.source_url)
      order by p.display_order, p.id),'[]') into it
    from v2_investor_principles p where p.firm_id=fid and p.is_current and not p.archived;
  if jsonb_array_length(it)>0 then secs := secs || jsonb_build_object('key','investors','items',it); end if;
  -- end What investors look for
  -- legal
  select coalesce(jsonb_agg(jsonb_build_object('grp',l.item_group,'head',coalesce(l.other_party,l.regulator_name)||' v. '||f.display_name,
      'note',concat_ws('. ',nullif(l.court,''),null),'role',l.side,'tone',null,'about',l.case_type,'case_type',l.case_type,'year',l.filed_year::text,'state',l.status,
      'status',case when l.closed_year is not null then l.status||' '||l.closed_year end,'summary',l.case_summary,'summary_url',l.summary_source_url,'summary_date',l.summary_date::text,
      'src',_v2_src(l.source_url,l.source_date,'CourtListener')) order by l.filed_year desc nulls last),'[]') into it
    from v2_legal_items l where l.firm_id=fid and l.is_current and not l.archived and not l.nothing_found and not coalesce(l.lead_only,false);
  if jsonb_array_length(it)>0 then secs := secs || jsonb_build_object('key','legal','title','Legal & regulatory','subtitle','Cases where the firm itself is a party, and regulator records.','renderer','legal','count',jsonb_array_length(it),'unit',case when jsonb_array_length(it)=1 then 'record' else 'records' end,'teaser',it->0->>'head','items',it); end if;
  -- press
  select coalesce(jsonb_agg(jsonb_build_object('url',n.source_url,'date',to_char(n.published_date,'Mon FMDD, YYYY'),'head',n.headline,'outlet',n.outlet,'tone',n.tone,
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
  -- E1: Team is the firm's founders and current leader (CEO, steward, managing partner) only (live rows). No partners, officers, or board seats.
  select coalesce(jsonb_agg(q.p order by q.ord),'[]') into it from (
    select r.row_id ord, jsonb_build_object('head',pe.person_name,'kind','team','role',r.title,
        'is_founder',r.is_founder,'linkedin_url',nullif(btrim(pe.linkedin_url),''),'x_url',nullif(btrim(pe.x_url),''),'linkedin_followers',pe.linkedin_followers,'x_followers',pe.x_followers) p
      from (
        select distinct on (person_id) *
          from v2_person_firm_roles
         where firm_id=fid and is_current and not archived and not nothing_found
           and (is_founder or v2_is_leader_title(title))
         order by person_id, is_founder desc, row_id
      ) r
      join v2_people pe on pe.person_id=r.person_id
     where pe.is_current and not pe.archived and not pe.nothing_found
  ) q;
  if jsonb_array_length(it)>0 then secs := secs || jsonb_build_object('key','people','title','Team','subtitle','','renderer','people','count',jsonb_array_length(it),'unit',case when jsonb_array_length(it)=1 then 'person' else 'people' end,'teaser',it->0->>'head','items',it); end if;
  -- Videos: up to 3 current YouTube interviews for this firm, most views first. None = no section.
  select coalesce(jsonb_agg(q.p order by q.rk),'[]') into it from (
    select row_number() over (order by v.view_count desc nulls last, v.interview_date desc nulls last, v.row_id) rk,
      jsonb_build_object('title',nullif(btrim(v.title),''),'channel',nullif(btrim(v.channel),''),'url',v.interview_url,
        'date',v.interview_date::text,'views',v.view_count) p
      from v2_interviews v
     where v.firm_id=fid and v.is_current and not v.archived and not v.nothing_found and not v.link_dead
       and nullif(btrim(v.title),'') is not null
       and lower(coalesce(v.interview_format,'video')) = 'video'
       and (v.interview_url ~* '^https?://((www|m|music)\.)?(youtube\.com|youtube-nocookie\.com)/' or v.interview_url ~* '^https?://youtu\.be/')
     order by v.view_count desc nulls last, v.interview_date desc nulls last, v.row_id
     limit 3
  ) q;
  if jsonb_array_length(it)>0 then secs := secs || jsonb_build_object('key','videos','count',jsonb_array_length(it),'items',it); end if;
  -- G5/G6 What founders say: only Checker-passed (is_current), not archived review rows, newest first.
  select coalesce(jsonb_agg(jsonb_build_object('body',nullif(trim(r.quote),''),'quote',nullif(trim(r.quote),''),
      'author',r.review_author,'name',r.review_author,'role',case when nullif(trim(r.reviewer_role_source_url),'') is not null then nullif(r.reviewer_role,'') end,'company',case when nullif(trim(r.reviewer_role_source_url),'') is not null then nullif(r.reviewer_company,'') end,
      'year',r.review_year,'date',coalesce(r.source_date::text,r.review_year::text),
      'url',r.source_url,'site',r.review_source_name,'outlet',r.review_source_name,'source_type',r.source_type,'tone',r.tone,
      'src',_v2_src(r.source_url,r.source_date,coalesce(r.review_source_name,r.source_type)))
      order by coalesce(r.source_date,make_date(r.review_year::int,1,1)) desc nulls last, r.row_id desc),'[]') into revs
    from v2_reviews r where r.firm_id=fid and r.is_current and not r.archived and not coalesce(r.nothing_found,false);
  return json_build_object('status','ok','open',true,'unchecked',false,'done',null,'source','v2',
    'firm',json_build_object('slug',f.slug,'name',f.display_name,'sec_name',coalesce(f.legal_name,f.display_name),'short_name',f.short_name,'hq',hq,'hq_country',case when upper(btrim(f.hq_country)) ~ '^[A-Z]{2}$' then upper(btrim(f.hq_country)) end,'website',f.website_url,'assets',null,
       'social',coalesce((select json_agg(json_build_object('platform',lower(s.platform),'url',s.account_url,
         'followers',s.follower_count,'is_rounded',s.is_rounded,'date_read',s.date_read,'latest_post_date',s.latest_post_date,
         'latest_post_link',s.latest_post_link,'source_url',s.source_url) order by s.follower_count desc)
         from v2_social_accounts s where s.firm_id=fid and s.is_current and not s.archived and not s.nothing_found
          and s.source_level=2 and s.follower_count is not null and s.date_read >= current_date - interval '12 months'),'[]'::json),'founded_year',f.founded_year,
       'industries',coalesce((select json_agg(i.industry_text order by i.position, i.id) from v2_firm_industries i where i.firm_id=fid and i.is_current and not i.archived),'[]'::json),
       'stages',coalesce((select json_agg(s.stage order by case lower(btrim(s.stage)) when 'pre-seed' then 1 when 'seed' then 2 when 'series a' then 3 when 'series b' then 4 when 'series c and later' then 5 when 'growth' then 6 else 7 end, s.id) from v2_firm_stages s where s.firm_id=fid and s.is_current and not s.archived),'[]'::json),
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
end $function$
;
