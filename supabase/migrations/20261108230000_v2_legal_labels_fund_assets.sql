-- Legal rows: source label from the URL host. A regulator heading is regulator + action.
-- Court headings, including a case filed against a person, stay other party v. the firm.
-- Fund assets: a passed queue item sets is_current, and v2_firm_page returns current
-- amounts whose date falls in 2021-2026. Then publish the approved Sequoia rows only.
-- No new tables or columns. Nothing is deleted. The v2 schema is not created here;
-- a database without these functions (CI) skips this.
do $mig$
declare
  d text;
  n text;
  old text;
  new text;
  qid bigint;
  allowed_q bigint[] := array[943,945,967,1033,1035,1037,1039,1041,1043,1045,1047,1049,1051,1053,1055];
  allowed_rows bigint[] := array[302,303,314,347,348,349,350,351,352,353,354,355,356,357,358];
  published int;
begin
  if to_regprocedure('public.v2_publish_queue_item(bigint)') is null
     or to_regprocedure('public.v2_firm_page(text)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;
  if to_regclass('public.v2_fund_assets') is null or to_regclass('public.v2_legal_items') is null then
    raise exception 'v2_firm_page exists but v2_fund_assets or v2_legal_items is missing';
  end if;

  select pg_get_functiondef('public.v2_publish_queue_item(bigint)'::regprocedure) into d;
  old := $old$  IF q.table_name = 'v2_fund_assets' THEN RETURN 'Confirmed: saved, not shown yet (M3.8 fund assets)'; END IF;
$old$;
  if position(old in d) > 0 then
    n := replace(d, old, '');
    if n = d or position('M3.8 fund assets' in n) > 0 then
      raise exception 'v2_publish_queue_item: fund asset patch did not apply';
    end if;
    execute n;
  elsif position('M3.8 fund assets' in d) > 0 then
    raise exception 'v2_publish_queue_item: fund asset no-op anchor missing';
  end if;

  select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;

  if position($a$when l.item_group = 'regulator' then nullif(btrim(concat_ws(' '$a$ in d) = 0 then
    old := $old$  select coalesce(jsonb_agg(jsonb_build_object('grp',l.item_group,'head',coalesce(l.other_party,l.regulator_name)||' v. '||f.display_name,
      'note',concat_ws('. ',nullif(l.court,''),null),'role',l.side,'tone',null,'about',l.case_type,'case_type',l.case_type,'year',l.filed_year::text,'state',l.status,
      'status',case when l.closed_year is not null then l.status||' '||l.closed_year end,'summary',l.case_summary,'summary_url',l.summary_source_url,'summary_date',l.summary_date::text,
      'src',_v2_src(l.source_url,l.source_date,'CourtListener')) order by l.filed_year desc nulls last),'[]') into it
    from v2_legal_items l where l.firm_id=fid and l.is_current and not l.archived and not l.nothing_found and not coalesce(l.lead_only,false);$old$;
    new := $new$  select coalesce(jsonb_agg(jsonb_build_object('grp',l.item_group,'head',
      case
        when l.item_group = 'regulator' then nullif(btrim(concat_ws(' ',
          case when l.regulator_name ~* 'department of the treasury' then 'U.S. Treasury' else nullif(btrim(l.regulator_name), '') end,
          case
            when coalesce(l.case_summary, '') ~* '\m(fine|fined|fines)\M' then 'fine'
            when coalesce(l.case_summary, '') ~* '\mpenalt' then 'penalty'
            when coalesce(l.case_summary, '') ~* '\m(ban|banned|barred)\M' then 'ban'
            when coalesce(l.case_summary, '') ~* '\m(charge|charged|charges)\M' then 'charge'
            when coalesce(l.case_summary, '') ~* '\msanction' then 'sanction'
          end)), '')
        else coalesce(l.other_party, l.regulator_name) || ' v. ' || f.display_name
      end,
      'note',concat_ws('. ',nullif(l.court,''),null),'role',l.side,'tone',null,'about',l.case_type,'case_type',l.case_type,'year',l.filed_year::text,'state',l.status,
      'status',case when l.closed_year is not null then l.status||' '||l.closed_year end,'summary',l.case_summary,'summary_url',l.summary_source_url,'summary_date',l.summary_date::text,
      'src',_v2_src(l.source_url,l.source_date,
        case
          when l.host ~ '(^|\.)courtlistener\.com$' then 'CourtListener'
          when l.host ~ '(^|\.)sec\.gov$' then 'SEC'
          when l.host ~ '(^|\.)treasury\.gov$' then 'Treasury'
          else nullif(l.host, '')
        end)) order by l.filed_year desc nulls last),'[]') into it
    from (
      select li.*, lower(regexp_replace(split_part(split_part(coalesce(li.source_url, ''), '://', 2), '/', 1), '^www\.', '')) as host
        from v2_legal_items li
       where li.firm_id=fid and li.is_current and not li.archived and not li.nothing_found and not coalesce(li.lead_only,false)
    ) l;$new$;
    if position(old in d) = 0 then
      raise exception 'v2_firm_page: legal anchor missing';
    end if;
    d := replace(d, old, new);
    if position($a$when l.item_group = 'regulator' then nullif(btrim(concat_ws(' '$a$ in d) = 0 then
      raise exception 'v2_firm_page: legal patch did not apply';
    end if;
  end if;

  if position($a$'fund_assets',json_build_object('n',coalesce(jsonb_array_length(fas),0)$a$ in d) = 0 then
    if position('revs jsonb;' in d) = 0 then
      raise exception 'v2_firm_page: declare anchor missing';
    end if;
    d := replace(d, 'revs jsonb;', 'revs jsonb; fas jsonb;');
    old := $old$  return json_build_object('status','ok','open',true,'unchecked',false,'done',null,'source','v2',$old$;
    new := $new$  select coalesce(jsonb_agg(jsonb_build_object(
      'name',fu.fund_name,
      'raised_usd',case when a.gross_assets_currency = 'USD' then a.gross_assets end,
      'raised_display',public._money_display(a.gross_assets, a.gross_assets_currency),
      'date',coalesce(a.as_of_date, a.source_date)::text,
      'url',a.source_url,
      'asset',true) order by fu.fund_name),'[]'::jsonb) into fas
    from v2_fund_assets a
    join v2_funds fu on fu.fund_id = a.fund_id
   where fu.firm_id = fid and a.is_current and not a.archived and not coalesce(a.nothing_found, false)
     and a.gross_assets > 0
     and extract(year from coalesce(a.as_of_date, a.source_date)) between 2021 and 2026;
  return json_build_object('status','ok','open',true,'unchecked',false,'done',null,'source','v2',$new$;
    if position(old in d) = 0 then
      raise exception 'v2_firm_page: return anchor missing';
    end if;
    d := replace(d, old, new);
    old := $old$'funds_sec',json_build_object('n',jsonb_array_length(funds),'items',funds),'funds_closed_12m'$old$;
    new := $new$'funds_sec',json_build_object('n',jsonb_array_length(funds),'items',funds),'fund_assets',json_build_object('n',coalesce(jsonb_array_length(fas),0),'items',coalesce(fas,'[]'::jsonb)),'funds_closed_12m'$new$;
    if position(old in d) = 0 then
      raise exception 'v2_firm_page: funds_sec anchor missing';
    end if;
    d := replace(d, old, new);
    if position($a$'fund_assets',json_build_object('n',coalesce(jsonb_array_length(fas),0)$a$ in d) = 0
       or position('fas jsonb;' in d) = 0 then
      raise exception 'v2_firm_page: fund asset patch did not apply';
    end if;
  end if;

  execute d;

  -- Publish only the approved Sequoia asset queue rows. 947 / asset 304 (the feeder) stays unpublished.
  if to_regclass('public.v2_checker_queue') is not null
     and exists (select 1 from v2_checker_queue where queue_id = 943) then
    if exists (
      select 1 from v2_checker_queue q
       where q.queue_id = any(allowed_q)
         and (q.table_name <> 'v2_fund_assets' or q.row_id <> all(allowed_rows) or q.row_id = 304 or q.status <> 'passed')
    ) then
      raise exception 'v2_fund_assets: approved queue rows do not match the Sequoia asset list';
    end if;
    if exists (select 1 from v2_checker_queue where queue_id = 947 and row_id <> 304) then
      raise exception 'queue 947 is not feeder asset 304';
    end if;
    foreach qid in array allowed_q loop
      perform public.v2_publish_queue_item(qid);
    end loop;
    select count(*) into published from v2_fund_assets
     where row_id = any(allowed_rows) and is_current and not archived;
    if published <> 15 then
      raise exception 'sequoia fund assets were not all published (got %)', published;
    end if;
    if exists (select 1 from v2_fund_assets where row_id = 304 and is_current) then
      raise exception 'feeder fund 304 must stay unpublished';
    end if;
  end if;
end
$mig$;
