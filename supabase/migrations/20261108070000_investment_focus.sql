-- Investment focus, one rule for every firm (F.11, Alex 2026-11-08, t4638u and t4639u).
-- v2_firm_page returns website labels with their source when v2_firm_industries has current rows.
-- When that list is empty it returns the top 5 sectors by distinct verified recorded deals, all dates.
-- Eligible archived history is included. Rejected and superseded facts, and missing sectors, are not.
-- Ties break alphabetically. This is not sector_12m and it does not call _v2_deals.
-- Lightspeed (firm_id 6) focus is written through v2_research_submit and the Checker, is_current true.
-- Nothing is deleted. The v2 schema is not created by repo migrations; CI skips this.
do $mig$
declare
  d text;
  n text;
  old text;
  new text;
  bot_key uuid;
  checker_key uuid;
  submitted jsonb;
  qid bigint;
  verdict jsonb;
  published int;
begin
  if to_regprocedure('public.v2_firm_page(text)') is null
     and to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;

  if to_regprocedure('public.v2_firm_page(text)') is not null then
    select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;
    if position('deal_sectors' in d) > 0 then
      raise notice 'v2_firm_page investment focus already patched';
    else
      old := $old$'industries',coalesce((select json_agg(i.industry_text order by i.position, i.id) from v2_firm_industries i where i.firm_id=fid and i.is_current and not i.archived),'[]'::json),$old$;
      new := $new$'industries',coalesce((select json_agg(json_build_object('industry_text',i.industry_text,'source_url',i.source_url) order by i.position, i.id) from v2_firm_industries i where i.firm_id=fid and i.is_current and not i.archived),'[]'::json),
       'deal_sectors',case when exists (select 1 from v2_firm_industries i where i.firm_id=fid and i.is_current and not i.archived) then '[]'::json
         else coalesce((select json_agg(json_build_object('sector',s,'n',n) order by n desc, sk) from (
           select sc.name s, lower(sc.name) sk, count(distinct d.deal_id)::int n
             from v2_deals d
             join v2_startups su on su.startup_id=d.startup_id
             join v2_startup_sectors ss on ss.startup_id=su.startup_id
             join v2_sector sc on sc.sector_id=ss.sector_id
            where d.firm_id=fid
              and not coalesce(d.nothing_found,false)
              and coalesce(d.archive_reason,'') !~* '^(checker rejected|superseded)'
              and ((coalesce(d.shown,true) and d.is_current and not d.archived) or d.archived)
              and not coalesce(su.nothing_found,false)
              and coalesce(su.archive_reason,'') !~* '^(checker rejected|superseded)'
              and (su.is_current or su.archived)
              and not coalesce(ss.nothing_found,false)
              and nullif(btrim(sc.name),'') is not null
              and coalesce(ss.archive_reason,'') !~* '^(checker rejected|superseded)'
              and ((ss.is_current and not ss.archived) or ss.archived)
            group by sc.name
            order by count(distinct d.deal_id) desc, lower(sc.name)
            limit 5) q),'[]'::json) end,$new$;
      if position(old in d) = 0 then
        raise exception 'v2_firm_page: industries anchor missing';
      end if;
      n := replace(d, old, new);
      if n = d or position('deal_sectors' in n) = 0 or position(old in n) > 0 then
        raise exception 'v2_firm_page: investment focus patch did not apply';
      end if;
      execute n;
    end if;
  end if;

  if to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is null
     or to_regprocedure('public.v2_checker_action(uuid,text,jsonb,boolean)') is null
     or to_regclass('public.v2_firm_industries') is null then
    return;
  end if;
  if not exists (select 1 from public.v2_firms where firm_id = 6) then
    raise exception 'Lightspeed firm_id 6 is missing';
  end if;

  if not exists (
    select 1 from public.v2_firm_industries
     where firm_id = 6 and not archived
       and source_url = 'https://lsvp.com/global-presence/lightspeed-united-states/'
  ) then
    select id into bot_key from bots.ingest_keys
     where bot_id = 'toxy-enricher' and active
     order by id limit 1;
    if bot_key is null then
      raise exception 'toxy-enricher key is missing; Lightspeed focus was not submitted';
    end if;
    submitted := public.v2_research_submit(bot_key, $items$[
      {"firm_id":6,"box":"F2","table":"v2_firm_industries","fact":{"industry_text":"Enterprise","position":1,"source_url":"https://lsvp.com/global-presence/lightspeed-united-states/","source_level":"2","source_date":"2026-11-07","source_type":"Firm website"}},
      {"firm_id":6,"box":"F2","table":"v2_firm_industries","fact":{"industry_text":"Consumer","position":2,"source_url":"https://lsvp.com/global-presence/lightspeed-united-states/","source_level":"2","source_date":"2026-11-07","source_type":"Firm website"}},
      {"firm_id":6,"box":"F2","table":"v2_firm_industries","fact":{"industry_text":"Health","position":3,"source_url":"https://lsvp.com/global-presence/lightspeed-united-states/","source_level":"2","source_date":"2026-11-07","source_type":"Firm website"}},
      {"firm_id":6,"box":"F2","table":"v2_firm_industries","fact":{"industry_text":"Fintech","position":4,"source_url":"https://lsvp.com/global-presence/lightspeed-united-states/","source_level":"2","source_date":"2026-11-07","source_type":"Firm website"}}
    ]$items$::jsonb, false);
    if coalesce(submitted->>'ok','') <> 'true' or coalesce((submitted->>'accepted')::int, 0) <> 4
       or coalesce((submitted->>'rejected')::int, 0) <> 0 then
      raise exception 'Lightspeed focus submit failed: %', submitted;
    end if;
  end if;

  if exists (
    select 1
      from public.v2_checker_queue c
      join public.v2_firm_industries i on i.id = c.row_id and i.submission_id = c.submission_id
     where c.table_name = 'v2_firm_industries' and c.status = 'open' and not c.archived
       and i.firm_id = 6
       and i.source_url = 'https://lsvp.com/global-presence/lightspeed-united-states/'
  ) then
    select id into checker_key from bots.ingest_keys
     where bot_id = 'toxy-checker' and active
     order by id limit 1;
    if checker_key is null then
      raise exception 'toxy-checker key is missing; Lightspeed focus was not published';
    end if;
  end if;
  for qid in
    select c.queue_id
      from public.v2_checker_queue c
      join public.v2_firm_industries i on i.id = c.row_id and i.submission_id = c.submission_id
     where c.table_name = 'v2_firm_industries' and c.status = 'open' and not c.archived
       and i.firm_id = 6
       and i.source_url = 'https://lsvp.com/global-presence/lightspeed-united-states/'
     order by i.position, c.queue_id
  loop
    verdict := public.v2_checker_action(checker_key, 'verdict', jsonb_build_object(
      'id', qid,
      'verdict', 'confirm',
      'reason', 'Lightspeed United States page states this focus. Read 2026-11-07.',
      'sources', jsonb_build_array('https://lsvp.com/global-presence/lightspeed-united-states/')
    ), false);
    if coalesce(verdict->>'ok','') <> 'true' or coalesce(verdict->>'outcome','') not like 'Confirmed:%' then
      raise exception 'Lightspeed focus confirm failed: %', verdict;
    end if;
  end loop;

  select count(*) into published
    from public.v2_firm_industries
   where firm_id = 6 and is_current and not archived
     and source_url = 'https://lsvp.com/global-presence/lightspeed-united-states/'
     and industry_text in ('Enterprise', 'Consumer', 'Health', 'Fintech');
  if published <> 4 then
    raise exception 'Lightspeed focus is not 4 current rows (found %)', published;
  end if;
end
$mig$;
