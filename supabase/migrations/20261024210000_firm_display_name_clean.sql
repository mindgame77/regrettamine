-- Firm display names: strip leftover entity words (Opco/ManCo, Management, Manager(s), Advisor(s)/Adviser(s), Advisory,
-- Operations, Legacy, Fund Management/Manager), trailing fund numerals / vintage years and truncated one-letter tails,
-- and fix casing (1sharpe -> 1Sharpe, A.capital -> A.Capital) on every path, including already-mixed-case input.
-- New firms get hq as 'City, ST' (US) or 'City, Country'. Slugs are untouched for existing firms.

alter function public.firm_display_name(text) rename to _firm_display_name_base;

create or replace function public.firm_display_name(p text)
 returns text language plpgsql immutable set search_path to 'public'
as $function$
declare s text := _firm_display_name_base(p); prev text; w text; out text := '';
begin
  if s is null then return null; end if;
  loop
    prev := s;
    s := regexp_replace(s, '\s+(fund\s+)?(i{1,3}|iv|v|vi{1,3}|ix|x{1,2}|xi{1,3}|xiv|xv|xvi{1,3}|xix|xx)$', '', 'i');
    s := regexp_replace(s, '\s+(19|20)\d\d$', '');
    s := regexp_replace(s, '\s+(opco|manco|legacy|operations|advisors?|advisers?|advisory|managers?|management(\s+holdings)?|ugp)$', '', 'i');
    s := regexp_replace(s, '^(.*[A-Za-z]{2,})\s+[A-Za-z]$', '\1');   -- truncated tail: 'Alpha Square Group S'
    s := regexp_replace(s, '\s+fund$', '', 'i');
    s := regexp_replace(s, '[\s,&\-]+$', '');
    exit when s = prev or s = '';
  end loop;
  if s = '' then s := _firm_display_name_base(p); end if;
  for w in select x from regexp_split_to_table(s, ' ') x loop
    if w ~ '^\d+[a-z]{3,}' then   -- 1sharpe -> 1Sharpe (but keep 5Y, 8VC, 3rd)
      w := substring(w from '^\d+') || upper(substring(w from '^\d+([a-z])')) || substring(w from '^\d+[a-z](.*)$');
    end if;
    while w ~ '[A-Za-z]\.[a-z]{2,}' loop   -- A.capital -> A.Capital
      w := regexp_replace(w, '([A-Za-z]\.)([a-z])', '\1' || upper(substring(w from '[A-Za-z]\.([a-z])[a-z]')));
    end loop;
    out := out || ' ' || w;
  end loop;
  return btrim(out);
end $function$;

create or replace function public.firm_hq_format(p_city text, p_state text, p_country text)
 returns text language sql immutable set search_path to 'public'
as $function$
  with v as (
    select nullif(btrim(regexp_replace(initcap(lower(coalesce(p_city, ''))), '^\d[\d ]*\s', '')), '') c,
           nullif(btrim(coalesce(p_state, '')), '') st, nullif(btrim(coalesce(p_country, '')), '') co),
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

CREATE OR REPLACE FUNCTION public.ensure_firm_for_registry(p_registry text, p_fill boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t text := _registry_target(p_registry); q research_queue; fid uuid; created boolean := false; researched boolean;
  dn text; base text; slg text; sfx int := 1; dom text; hq text; linked int := 0;
begin
  select * into q from research_queue where registry_id = t;
  if q.registry_id is null then return null; end if;
  researched := exists (select 1 from research_submissions s where s.registry_id in (t, p_registry) and s.valid);
  if nullif(q.sec_crd, '') is not null then
    select id into fid from firms where sec_crd = q.sec_crd and deleted_at is null order by published desc limit 1;
  end if;
  if fid is null then select id into fid from firms where registry_id = t and deleted_at is null; end if;
  if fid is not null then
    update firms set registry_id = t where id = fid and registry_id is null and not exists (select 1 from firms o where o.registry_id = t);
    if researched then
      update firms set published = true where id = fid and not published and not coalesce(is_test, false) and data_status = 'real';
    end if;
  else
    dn := coalesce(firm_display_name(q.name), q.name);
    base := coalesce(_slugify(dn), lower(t)); slg := base;
    while exists (select 1 from firms where slug = slg) loop sfx := sfx + 1; slg := base || '-' || sfx; end loop;
    dom := substring(lower(btrim(coalesce(q.website, ''))) from '^(?:[a-z]+://)?(?:www\.)?([^/:?#\s]+)');
    if dom is null or dom !~ '\.' or dom ~ '(^|\.)(linkedin|x|twitter|instagram|facebook|youtube|crunchbase|medium|github|angel|wellfound|pitchbook)\.(com|co|io)$' then dom := null; end if;
    hq := firm_hq_format(q.hq_city, q.state, q.country);
    insert into firms (slug, name, display_name, legal_name, hq, sec_crd, primary_domain, firm_type, data_status, source_system, external_id,
                       registry_id, published)
    values (slg, dn, dn, q.name, hq, nullif(q.sec_crd, ''), dom, case when q.firm_type = 'vc' then 'VC' end, 'real', 'research', t,
            t, researched)
    returning id into fid;
    created := true;
    insert into firm_check_rows (firm_id, n, title, descr, state, count_label)
    select fid, x.n, x.title, x.descr, 'nc', null from (values
      (1, 'Sanctions', 'Government lists of people and companies you can''t do business with.'),
      (2, 'Terrorism financing lists', 'Lists of people and groups linked to funding terrorism.'),
      (3, 'Export and investment restrictions', 'Trade or investment bans, e.g. deals with military-linked firms.'),
      (4, 'Financial regulator actions', 'Fines, bans and charges from financial regulators.'),
      (5, 'Money laundering penalties', 'Anti-money-laundering fines and enforcement.'),
      (6, 'US court records', 'Federal and state cases, civil and criminal.'),
      (7, 'Court records worldwide', 'Cases outside the U.S.'),
      (8, 'Registration check', 'Registered with the regulator as an investment adviser, and active.'),
      (9, 'People behind the fund', 'Partners and owners, each checked against the lists above.'),
      (10, 'Political ties', 'People at the firm who held government or political roles.')) x(n, title, descr)
    on conflict (firm_id, n) do nothing;
  end if;
  -- link enrichments / search log rows that arrived before the page existed (rows are not copied, so re-sends never duplicate)
  update research_enrichments set firm_id = fid where firm_id is null and registry_id in (t, p_registry);
  get diagnostics linked = row_count;
  update search_log set firm_id = fid where firm_id is null and registry_id in (t, p_registry);
  if p_fill or created then
    begin perform apply_checks_for_firm(fid); exception when others then raise warning 'ensure_firm %: checks: %', t, sqlerrm; end;
    begin perform promote_bot_facts(fid); exception when others then raise warning 'ensure_firm %: bot facts: %', t, sqlerrm; end;
  end if;
  if p_fill or created or linked > 0 then
    begin perform promote_enrichment(fid); exception when others then raise warning 'ensure_firm %: enrichment: %', t, sqlerrm; end;
  end if;
  return fid;
end $function$;
