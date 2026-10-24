-- HQ display: research_queue.country sometimes carries internal list tags (US-SMALL, US-CUR) or a bare ISO code (IN).
-- firm_hq_format treated those as a foreign country name and printed them ("St. Louis, US-SMALL", "Mumbai, IN").
-- Fix the formatter (US-* tags = United States -> "City, ST"; IN = India) and recompute the derived firms.hq
-- for rows still holding the old tagged value. research_queue (bot raw data) is not touched.
create or replace function public.firm_hq_format(p_city text, p_state text, p_country text)
 returns text language sql immutable set search_path to 'public'
as $function$
  with v as (
    select nullif(btrim(regexp_replace(initcap(lower(coalesce(p_city, ''))), '^\d[\d ]*\s', '')), '') c,
           nullif(btrim(coalesce(p_state, '')), '') st,
           case when btrim(coalesce(p_country, '')) ~* '^(US|USA)([-_ ][A-Z0-9]+)*$' then 'US'
                when upper(btrim(coalesce(p_country, ''))) = 'IN' then 'India'
                else nullif(btrim(coalesce(p_country, '')), '') end co),
  m(n, a) as (values ('alabama','AL'),('alaska','AK'),('arizona','AZ'),('arkansas','AR'),('california','CA'),('colorado','CO'),
    ('connecticut','CT'),('delaware','DE'),('district of columbia','DC'),('florida','FL'),('georgia','GA'),('hawaii','HI'),('idaho','ID'),
    ('illinois','IL'),('indiana','IN'),('iowa','IA'),('kansas','KS'),('kentucky','KY'),('louisiana','LA'),('maine','ME'),('maryland','MD'),
    ('massachusetts','MA'),('michigan','MI'),('minnesota','MN'),('mississippi','MS'),('missouri','MO'),('montana','MT'),('nebraska','NE'),
    ('nevada','NV'),('new hampshire','NH'),('new jersey','NJ'),('new mexico','NM'),('new york','NY'),('north carolina','NC'),
    ('north dakota','ND'),('ohio','OH'),('oklahoma','OK'),('oregon','OR'),('pennsylvania','PA'),('rhode island','RI'),
    ('south carolina','SC'),('south dakota','SD'),('tennessee','TN'),('texas','TX'),('utah','UT'),('vermont','VT'),('virginia','VA'),
    ('washington','WA'),('west virginia','WV'),('wisconsin','WI'),('wyoming','WY'))
  select nullif(concat_ws(', ',
           case when v.c ~* '^washington,? d\.?c\.?$' then 'Washington' else v.c end,
           case when coalesce(v.co, 'US') in ('United States', 'US', 'USA', 'U.S.', 'United States of America')
                then coalesce((select a from m where n = lower(v.st)), upper(v.st))
                else v.co end), '')
  from v
$function$;

-- Derived field only: recompute firms.hq where it still shows a raw tag produced by the old formatter.
update firms f set hq = firm_hq_format(q.hq_city, q.state, q.country)
from research_queue q
where q.registry_id = f.registry_id
  and (f.hq ~ ', US[-_][A-Z0-9]+$' or (f.hq ~ ', IN$' and upper(btrim(q.country)) = 'IN'))
  and f.hq is distinct from firm_hq_format(q.hq_city, q.state, q.country);
