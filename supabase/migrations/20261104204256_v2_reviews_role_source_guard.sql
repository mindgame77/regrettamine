-- The v2 schema is not created by repo migrations; on a database without v2_reviews (CI) this is a no-op.
-- Applied to production via Supabase as v2_reviews_role_source_guard (20261104204256).
do $mig$
begin
  if to_regclass('public.v2_reviews') is null then raise notice 'v2 schema missing, skipped'; return; end if;
  execute $mx$
-- G5.2 fixes (Alex 2026-11-04 12:40 PM PT). Undo: /workspace/backups/v2_reviews_role_source_guard_undo_20261104204245.sql
-- Row 14: role source -> TechCrunch 2024-08-28 ("Marty Kausas, Pylon's CEO and co-founder").
update public.v2_reviews set reviewer_role_source_url='https://techcrunch.com/2024/08/28/pylon-lands-17m-investment-to-build-a-full-service-b2b-customer-service-platform/' where row_id=14;
-- Row 15: no single source states both CEO and "Ketone-IQ"; company blanked, CEO kept (X bio "CEO/co-founder @ketone").
update public.v2_reviews set reviewer_company=null where row_id=15;
-- Row 19: HN profile states "Chris Coyne | Keybase"; used as the name and company source.
update public.v2_reviews set review_author='Chris Coyne', reviewer_role_source_url='https://news.ycombinator.com/user?id=malgorithms' where row_id=19;
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
  select coalesce(jsonb_agg(jsonb_build_object('body',nullif(trim(r.quote),''),'quote',nullif(trim(r.quote),''),
      'author',r.review_author,'name',r.review_author,'role',case when nullif(trim(r.reviewer_role_source_url),'') is not null then nullif(r.reviewer_role,'') end,'company',case when nullif(trim(r.reviewer_role_source_url),'') is not null then nullif(r.reviewer_company,'') end,
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
CREATE OR REPLACE FUNCTION public.v2_research_submit(p_key_id uuid, p_items jsonb, p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
DECLARE
  ik bots.ingest_keys; bk public.v2_bot_keys; bot text; batch bigint;
  it jsonb; idx int := -1; firmkey text; firms text[] := '{}'; refused jsonb := '[]'; results jsonb := '[]';
  tbl text; box text; fact jsonb; p jsonb; k text; v jsonb; reason text; sid bigint; fid bigint; res jsonb;
  sec_id smallint; o_site text;
  pkcol text; newid bigint; cols text; refs jsonb := '{}'; q_kind text; o jsonb; n jsonb; upd jsonb; diff boolean;
  rej_today int; firms_hour int; frz text; acc int := 0; rejn int := 0; held int := 0;
  src_tables text[] := ARRAY['v2_funds','v2_fund_assets','v2_lp_commitments','v2_startups','v2_startup_sectors','v2_deals','v2_people',
    'v2_person_firm_roles','v2_board_seats','v2_interviews','v2_legal_items','v2_sec_registration','v2_sec_fact_pills','v2_social_accounts',
    'v2_news_items','v2_reviews','v2_firm_aum','v2_firm_contacts','v2_firm_registry_ids'];
  firm_fields jsonb := '{"legal_name":"legal_name_source","founded_year":"founded_year_source","thesis_text":"thesis_source","hq_street":"hq_source","hq_suite":"hq_source","hq_city":"hq_source","hq_state":"hq_source","hq_postal":"hq_source","hq_country":"hq_source","website_url":null,"short_name":null}';
  blocked text[] := ARRAY['row_id','submission_id','archived','archive_reason','created_at','is_current','source_url_norm','archived_url_norm','link_dead','website_source'];
  src_keys text[] := ARRAY['source_url','source_level','source_date','source_date_precision','source_date_is_found_date','source_type','source_owner','archived_url','nothing_found'];
BEGIN
  SELECT * INTO ik FROM bots.ingest_keys WHERE id = p_key_id AND active;
  IF NOT FOUND OR ik.bot_id IS NULL THEN RETURN jsonb_build_object('ok',false,'error','this key is not linked to a bot'); END IF;
  bot := ik.bot_id;
  INSERT INTO public.v2_bot_keys (bot_name, key_hash) VALUES (bot, ik.key_hash)
    ON CONFLICT (bot_name) DO UPDATE SET key_hash = EXCLUDED.key_hash RETURNING * INTO bk;
  IF bk.frozen THEN
    RETURN jsonb_build_object('ok',false,'error',format('Key frozen: %s, %s', coalesce(bk.freeze_reason,'no reason'), to_char(bk.freeze_date AT TIME ZONE 'America/Los_Angeles','YYYY-MM-DD HH24:MI "PT"')));
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN RETURN jsonb_build_object('ok',false,'error','items must be a non-empty array'); END IF;
  IF jsonb_array_length(p_items) > 500 THEN RETURN jsonb_build_object('ok',false,'error','max 500 items per batch'); END IF;
  batch := nextval('public.v2_batch_seq');

  BEGIN  -- whole batch; rolled back at the end when p_dry_run
  FOR it IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    idx := idx + 1; reason := NULL; sid := NULL; newid := NULL; q_kind := NULL; res := NULL;
    IF jsonb_typeof(it) <> 'object' THEN
      results := results || jsonb_build_object('index',idx,'status','Rejected: item must be an object'); CONTINUE; END IF;
    firmkey := coalesce(it->>'firm_id', it->>'firm_ref');
    IF firmkey IS NULL THEN
      results := results || jsonb_build_object('index',idx,'status','Rejected: firm_id (existing firm) or firm_ref (new firm) required'); CONTINUE; END IF;
    IF NOT firmkey = ANY(firms) THEN
      IF cardinality(firms) >= 10 THEN
        refused := refused || jsonb_build_object('index',idx,'firm',firmkey,'status','Refused: batch over 10 firms; firms 11+ are refused, send them in the next batch (I1.5)'); CONTINUE; END IF;
      firms := firms || firmkey;
    END IF;
    tbl := it->>'table'; box := it->>'box'; fact := coalesce(it->'fact','{}');
    fid := CASE WHEN (it->>'firm_id') ~ '^\d+$' THEN (it->>'firm_id')::bigint END;
    IF it->>'firm_id' IS NOT NULL AND fid IS NULL THEN reason := 'firm_id must be a number';
    ELSIF box IS NULL OR box !~ '^[A-Z]{1,3}[0-9]{1,3}[a-z]?$' THEN reason := 'box required (e.g. F12)';
    ELSIF tbl IS NULL OR NOT (tbl = ANY(src_tables) OR tbl = 'v2_firms') THEN reason := format('unknown table "%s" (P9)', coalesce(tbl,''));
    ELSIF jsonb_typeof(fact) <> 'object' THEN reason := 'fact must be an object';
    ELSIF fid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.v2_firms WHERE firm_id = fid) THEN reason := format('firm_id %s not found', fid);
    END IF;
    -- source checks (R2, P1, P2, S1-S4)
    IF reason IS NULL THEN
      fact := fact || jsonb_build_object('source_owner', coalesce(fact->>'source_owner', bot));
      IF coalesce(fact->>'source_url','') = '' THEN reason := 'no source link (source_url)';
      ELSIF (fact->>'source_url') ~* '(google\.[a-z.]+/search|bing\.com/search|duckduckgo\.com/\?|grok\.com|x\.com/i/grok|chatgpt\.com|perplexity\.ai/search)' THEN reason := 'source_url is a search/chat page; cite the page itself';
      ELSIF (fact->>'source_url') !~* '^(https?://)?(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(/[^\s]*)?$' THEN reason := 'source_url is not a valid link';
      ELSIF coalesce(fact->>'source_level','') !~ '^[1-4]$' THEN reason := 'no source level (source_level must be 1, 2, 3 or 4)';
      ELSIF coalesce(fact->>'source_date','') !~ '^\d{4}-\d{2}-\d{2}$' THEN reason := 'no source date (source_date YYYY-MM-DD)';
      ELSIF coalesce(fact->>'source_type','') = '' THEN reason := 'no source type (source_type)';
      END IF;
      IF reason IS NULL THEN
        BEGIN IF (fact->>'source_date')::date > current_date THEN reason := 'source_date is in the future'; END IF;
        EXCEPTION WHEN others THEN reason := 'source_date is not a real date'; END;
      END IF;
    END IF;
    -- G5.2 (Alex 2026-11-04 12:40 PM PT): a review's reviewer_role / reviewer_company needs a valid reviewer_role_source_url
    IF reason IS NULL AND tbl = 'v2_reviews' AND (coalesce(btrim(fact->>'reviewer_role'),'') <> '' OR coalesce(btrim(fact->>'reviewer_company'),'') <> '') THEN
      IF coalesce(btrim(fact->>'reviewer_role_source_url'),'') = '' THEN reason := 'reviewer_role/reviewer_company sent without reviewer_role_source_url (G5.2)';
      ELSIF (fact->>'reviewer_role_source_url') ~* '(google\.[a-z.]+/search|bing\.com/search|duckduckgo\.com/\?|grok\.com|x\.com/i/grok|chatgpt\.com|perplexity\.ai/search)' THEN reason := 'reviewer_role_source_url is a search/chat page; cite the page itself (G5.2)';
      ELSIF (fact->>'reviewer_role_source_url') !~* '^https?://(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(/[^\s]*)?$' THEN reason := 'reviewer_role_source_url is not a valid link (G5.2)';
      END IF;
    END IF;
    -- 015: sector rows may name the ST5 word ("sector") instead of sector_id; max 2 per startup
    IF reason IS NULL AND tbl = 'v2_startup_sectors' AND fact ? 'sector' THEN
      SELECT sector_id INTO sec_id FROM public.v2_sector WHERE lower(name) = lower(trim(fact->>'sector'));
      IF sec_id IS NULL THEN reason := format('unknown sector "%s" (use one of the 18 ST5 sectors)', fact->>'sector');
      ELSIF fact ? 'sector_id' AND (fact->>'sector_id') IS DISTINCT FROM sec_id::text THEN reason := 'sector and sector_id disagree';
      ELSE fact := (fact - 'sector') || jsonb_build_object('sector_id', sec_id); END IF;
    END IF
;
    IF reason IS NULL THEN
      SELECT string_agg(key, ', ') INTO k FROM jsonb_object_keys(fact) key WHERE key = ANY(blocked) OR key LIKE '%\_norm';
      IF k IS NOT NULL THEN reason := 'field not allowed (set by the database): '||k; END IF;
    END IF;
    IF reason IS NULL AND tbl <> 'v2_firms' THEN
      SELECT string_agg(key, ', ') INTO k FROM jsonb_object_keys(fact) key
        WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema='public' AND c.table_name=tbl AND c.column_name=key);
      IF k IS NOT NULL THEN reason := 'unknown field: '||k; END IF;
    END IF;
    -- resolve @refs from earlier items of this batch
    p := '{}';
    IF reason IS NULL THEN
      FOR k, v IN SELECT * FROM jsonb_each(fact) LOOP
        IF jsonb_typeof(v) = 'string' AND left(v#>>'{}',1) = '@' THEN
          IF refs ? substr(v#>>'{}',2) THEN p := p || jsonb_build_object(k, refs->substr(v#>>'{}',2));
          ELSE reason := format('ref %s not found in this batch (the item that makes it was rejected, held, or comes later)', v#>>'{}'); EXIT; END IF;
        ELSE p := p || jsonb_build_object(k, v); END IF;
      END LOOP;
      IF tbl <> 'v2_firms' AND p ? 'firm_id' = false AND EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema='public' AND c.table_name=tbl AND c.column_name='firm_id') THEN
        p := p || jsonb_build_object('firm_id', fid); END IF;
    END IF;

    INSERT INTO public.v2_research_submissions (batch_id, firm_id, bot_key_id, target_box, payload)
      VALUES (batch, fid, bk.bot_key_id, coalesce(box,'?'), jsonb_build_object('target_table',tbl,'fact',coalesce(it->'fact','{}'::jsonb),'firm_ref',it->>'firm_ref','ref',it->>'ref','origin',it->>'note','source_owner',coalesce(fact->>'source_owner',bot),'item_index',idx))
      RETURNING submission_id INTO sid;

    IF reason IS NULL AND tbl = 'v2_firms' THEN
      IF fid IS NULL THEN  -- only the publish step creates a firm (F1.3.1)
        reason := NULL; q_kind := 'new-firm';
        INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, new_value) VALUES (sid, NULL, 'new-firm', tbl, p);
        UPDATE public.v2_research_submissions SET status = 'Held: new firm waits for the Checker (F1.3.1)' WHERE submission_id = sid;
        INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, submission_id, new_value, result) VALUES (bot, NULL, box, tbl, sid, p, 'Blocked: held, new firm waits for the Checker');
        held := held + 1;
        results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Held: new firm waits for the Checker (F1.3.1)','checker_queued','new-firm');
        CONTINUE;
      END IF;
      SELECT string_agg(key, ', ') INTO k FROM jsonb_object_keys(p) key WHERE NOT (key = ANY(src_keys) OR firm_fields ? key);
      IF k IS NOT NULL THEN reason := 'unknown firm field: '||k||' (allowed: '||(SELECT string_agg(x,', ') FROM jsonb_object_keys(firm_fields) x)||')'; END IF;
      IF reason IS NULL AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p) key WHERE firm_fields ? key) THEN reason := 'no firm field to set'; END IF;
      IF reason IS NULL THEN
        SELECT to_jsonb(f) INTO o FROM public.v2_firms f WHERE firm_id = fid;
        upd := '{}'; diff := false;
        FOR k, v IN SELECT * FROM jsonb_each(p) WHERE firm_fields ? key LOOP
          upd := upd || jsonb_build_object(k, v);
          IF firm_fields->>k IS NOT NULL THEN upd := upd || jsonb_build_object(firm_fields->>k, jsonb_build_object('url',p->>'source_url','level',(p->>'source_level')::int,'date',p->>'source_date')); END IF;
          IF o->k IS NOT NULL AND o->k <> 'null'::jsonb AND (o->>k) IS DISTINCT FROM (v#>>'{}') THEN diff := true; END IF;
        END LOOP;
        IF diff THEN  -- changed key fact: never overwrite directly (P15)
          INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, old_value, new_value)
            VALUES (sid, fid, 'changed-key-fact', tbl, fid, (SELECT jsonb_object_agg(x, o->x) FROM jsonb_object_keys(upd) x), upd);
          UPDATE public.v2_research_submissions SET status = 'Held: changed key fact waits for the Checker (P15)' WHERE submission_id = sid;
          INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result) VALUES (bot, fid, box, tbl, fid, sid, o, upd, 'Blocked: held, changed key fact waits for the Checker');
          held := held + 1;
          results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Held: changed key fact waits for the Checker (P15)','checker_queued','changed-key-fact');
          CONTINUE;
        END IF;
        BEGIN
          EXECUTE format('UPDATE public.v2_firms t SET (%s) = (SELECT %s FROM jsonb_populate_record(NULL::public.v2_firms, $1)), last_checked_date = current_date WHERE firm_id = $2 RETURNING to_jsonb(t)',
            (SELECT string_agg(format('%I',x),',') FROM jsonb_object_keys(upd) x), (SELECT string_agg(format('%I',x),',') FROM jsonb_object_keys(upd) x)) INTO n USING upd, fid;
          UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = sid;
          INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
            VALUES (bot, fid, box, tbl, fid, sid, (SELECT jsonb_object_agg(x, o->x) FROM jsonb_object_keys(upd) x), (SELECT jsonb_object_agg(x, n->x) FROM jsonb_object_keys(upd) x), 'Accepted');
          acc := acc + 1;
          results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,'row_id',fid);
          CONTINUE;
        EXCEPTION WHEN others THEN reason := left(SQLERRM, 300); END;
      END IF;
    END IF;

    -- 015: sector row for a startup: max 2 per startup (11. startup_sectors), startup must exist
    IF reason IS NULL AND tbl = 'v2_startup_sectors' THEN
      IF (p->>'startup_id') !~ '^\d+$' OR NOT EXISTS (SELECT 1 FROM public.v2_startups WHERE startup_id = (p->>'startup_id')::bigint AND NOT archived) THEN
        reason := format('startup_id %s not found', coalesce(p->>'startup_id',''));
      ELSIF EXISTS (SELECT 1 FROM public.v2_startup_sectors WHERE startup_id = (p->>'startup_id')::bigint AND sector_id = (p->>'sector_id')::smallint) THEN
        reason := 'sector already set for this startup';
      ELSIF (SELECT count(*) FROM public.v2_startup_sectors WHERE startup_id = (p->>'startup_id')::bigint AND NOT archived) >= 2 THEN
        reason := 'startup already has 2 sectors (max 2)';
      END IF;
    END IF;
    -- 015: website fill for an EXISTING startup (fact has startup_id): fills an empty website_url only; never a new startup, never overwrites
    IF reason IS NULL AND tbl = 'v2_startups' AND p ? 'startup_id' THEN
      SELECT string_agg(key, ', ') INTO k FROM jsonb_object_keys(p) key WHERE NOT (key = ANY(src_keys) OR key IN ('startup_id','website_url'));
      IF k IS NOT NULL THEN reason := 'existing startup: only website_url can be filled (not allowed: '||k||')';
      ELSIF coalesce(p->>'website_url','') = '' THEN reason := 'existing startup: website_url required';
      ELSIF (p->>'startup_id') !~ '^\d+$' THEN reason := 'startup_id must be a number';
      ELSE
        SELECT to_jsonb(s) INTO o FROM public.v2_startups s WHERE startup_id = (p->>'startup_id')::bigint AND NOT archived;
        IF o IS NULL THEN reason := format('startup_id %s not found', p->>'startup_id');
        ELSE
          o_site := nullif(o->>'website_url','');
          IF o_site IS NOT NULL THEN
            IF lower(regexp_replace(regexp_replace(o_site,'^(https?://)?(www\.)?',''),'/+$','')) = lower(regexp_replace(regexp_replace(p->>'website_url','^(https?://)?(www\.)?',''),'/+$','')) THEN
              UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = sid;
              INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
                VALUES (bot, fid, box, tbl, (o->>'startup_id')::bigint, sid, jsonb_build_object('website_url',o_site), jsonb_build_object('website_url',p->>'website_url'), 'Accepted');
              acc := acc + 1;
              results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,'row_id',(o->>'startup_id')::bigint,'note','website already set to the same site; nothing changed');
              CONTINUE;
            END IF;
            reason := 'startup already has a different website_url; never overwritten (P15)';
          ELSIF (p->>'source_level') = '4' THEN reason := 'website fill needs source_level 1-3';
          ELSE
            BEGIN
              UPDATE public.v2_startups t SET website_url = p->>'website_url',
                  website_source = jsonb_build_object('url',p->>'source_url','level',(p->>'source_level')::int,'date',p->>'source_date','type',p->>'source_type','owner',p->>'source_owner','submission_id',sid)
                WHERE startup_id = (o->>'startup_id')::bigint AND coalesce(website_url,'') = '' RETURNING to_jsonb(t) INTO n;
              IF n IS NULL THEN reason := 'website_url was filled meanwhile; never overwritten (P15)'; END IF;
            EXCEPTION WHEN unique_violation THEN reason := 'another startup already has this website domain (no duplicate startups)';
                      WHEN others THEN reason := left(SQLERRM, 300); END;
            IF reason IS NULL THEN
              UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = sid;
              INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
                VALUES (bot, fid, box, tbl, (o->>'startup_id')::bigint, sid, jsonb_build_object('website_url',NULL), jsonb_build_object('website_url',n->>'website_url','website_source',n->'website_source'), 'Accepted');
              acc := acc + 1;
              IF it->>'ref' IS NOT NULL THEN refs := refs || jsonb_build_object(it->>'ref', (o->>'startup_id')::bigint); END IF;
              results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,'row_id',(o->>'startup_id')::bigint,'note','website filled on existing startup');
              CONTINUE;
            END IF;
          END IF;
        END IF;
      END IF;
    END IF;

    IF reason IS NULL THEN
      IF (p->>'source_level') = '4' THEN p := p || '{"archived":true,"archive_reason":"L4 kept archived (R2)"}'; END IF;
      p := p || jsonb_build_object('submission_id', sid);
      SELECT string_agg(format('%I', key), ',') INTO cols FROM jsonb_object_keys(p) key;
      BEGIN
        EXECUTE format('INSERT INTO public.%I AS t (%s) SELECT %s FROM jsonb_populate_record(NULL::public.%I, $1) RETURNING to_jsonb(t)', tbl, cols, cols, tbl) INTO res USING p;
      EXCEPTION WHEN others THEN reason := left(SQLERRM, 300); END;
    END IF;

    IF reason IS NOT NULL THEN
      UPDATE public.v2_research_submissions SET status = 'Rejected: '||reason WHERE submission_id = sid;
      INSERT INTO public.v2_rejected_rows (payload, target_table, error_message, source_owner, submission_id, status)
        VALUES (coalesce(it->'fact','{}'::jsonb) || jsonb_build_object('_item', it - 'fact'), coalesce(tbl,'?'), reason, left(coalesce(fact->>'source_owner',bot),200), sid, 'new');
      INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, submission_id, new_value, result)
        VALUES (bot, fid, coalesce(box,'?'), coalesce(tbl,'?'), sid, it, 'Rejected: '||reason);
      rejn := rejn + 1;
      results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Rejected: '||reason);
      CONTINUE;
    END IF;

    pkcol := CASE tbl WHEN 'v2_funds' THEN 'fund_id' WHEN 'v2_startups' THEN 'startup_id' WHEN 'v2_people' THEN 'person_id'
                      WHEN 'v2_deals' THEN 'deal_id' WHEN 'v2_legal_items' THEN 'legal_item_id' ELSE 'row_id' END;
    newid := (res->>pkcol)::bigint;
    -- 011: new rows stay hidden until the Checker passes them (v2_publish_queue_item sets is_current/shown)
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name=tbl AND column_name='is_current') THEN
      EXECUTE format('UPDATE public.%I SET is_current = false WHERE submission_id = $1', tbl) USING sid;
    END IF;
    IF tbl = 'v2_deals' THEN UPDATE public.v2_deals SET shown = false WHERE submission_id = sid; END IF;
    IF it->>'ref' IS NOT NULL THEN refs := refs || jsonb_build_object(it->>'ref', newid); END IF;
    UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = sid;
    INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
      VALUES (bot, fid, box, tbl, newid, sid, NULL, res, 'Accepted');
    -- name-only rows go to the Checker (glossary 30, C4.2)
    IF NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p) key WHERE NOT (key = ANY(src_keys) OR key IN ('firm_id','submission_id','archived','archive_reason') OR key LIKE '%\_name')) THEN
      q_kind := 'name-only';
      INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, new_value) VALUES (sid, fid, 'name-only', tbl, newid, res);
    ELSE  -- 011: every accepted item goes live only after the Checker passes it (Checker-first, R4.1; covers 010 LP rows too)
      q_kind := 'accepted-item';
      INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, new_value) VALUES (sid, fid, 'accepted-item', tbl, newid, res);
    END IF;
    acc := acc + 1;
    results := results || jsonb_strip_nulls(jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,'row_id',newid,'checker_queued',q_kind,
      'note',CASE WHEN (p->>'source_level')='4' THEN 'L4: kept archived (R2)' END));
  END LOOP;

  -- freeze rules (I2.7)
  SELECT count(*) INTO rej_today FROM public.v2_research_submissions WHERE bot_key_id = bk.bot_key_id AND status LIKE 'Rejected:%'
    AND received_at >= date_trunc('day', now() AT TIME ZONE 'America/Los_Angeles') AT TIME ZONE 'America/Los_Angeles';
  SELECT count(DISTINCT coalesce(firm_id::text, payload->>'firm_ref')) INTO firms_hour FROM public.v2_research_submissions
    WHERE bot_key_id = bk.bot_key_id AND received_at > now() - interval '1 hour';
  frz := CASE WHEN rej_today >= 10 THEN format('%s rejections today', rej_today) WHEN firms_hour > 100 THEN format('%s firms in the last hour', firms_hour) END;
  IF frz IS NOT NULL AND NOT p_dry_run THEN
    UPDATE public.v2_bot_keys SET frozen = true, freeze_date = now(), freeze_reason = frz,
      freeze_count_7d = CASE WHEN freeze_date > now() - interval '7 days' THEN coalesce(freeze_count_7d,0) + 1 ELSE 1 END
      WHERE bot_key_id = bk.bot_key_id;
    INSERT INTO public.v2_change_log (actor, box, table_name, row_id, new_value, result)
      VALUES ('v2_research_submit', 'I2', 'v2_bot_keys', bk.bot_key_id, jsonb_build_object('bot',bot,'frozen',true,'reason',frz), 'Blocked: Key frozen: '||frz);
  END IF;

  IF p_dry_run THEN RAISE EXCEPTION 'v2_dry_run_rollback'; END IF;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'v2_dry_run_rollback' THEN RAISE; END IF;
  END;

  RETURN jsonb_strip_nulls(jsonb_build_object('ok', true, 'bot_id', bot, 'dry_run', p_dry_run, 'batch_id', CASE WHEN NOT p_dry_run THEN batch END,
    'accepted', acc, 'rejected', rejn, 'held', held, 'refused', jsonb_array_length(refused), 'firms', cardinality(firms),
    'results', results, 'refused_items', CASE WHEN jsonb_array_length(refused) > 0 THEN refused END,
    'key_frozen', CASE WHEN frz IS NOT NULL AND NOT p_dry_run THEN format('Key frozen: %s, %s', frz, to_char(now() AT TIME ZONE 'America/Los_Angeles','YYYY-MM-DD HH24:MI "PT"')) END,
    'would_freeze', CASE WHEN frz IS NOT NULL AND p_dry_run THEN frz END));
END $function$;
$mx$;
end
$mig$;
