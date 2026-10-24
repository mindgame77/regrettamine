-- Readable names for source labels (approved by Alex, Oct 23).
-- 1. source_label_map: raw domain (+ optional URL pattern) -> readable name. Subdomains fall back to the longest mapped parent
--    (news.foo.com -> foo.com), so new bot data shows readable names without touching the bot's raw rows.
-- 2. source_label(label, url): display-time mapping used by _src, firm_details and _sec_items. Non-domain labels pass through.
-- 3. One-off rewrite of stored fact_sources.label / sources.publisher that are raw domains.
--    Backup of the old values: /workspace/backups/pre-source-labels-2026-10-23/ (fact_sources_label.*, sources_publisher.*).

create table if not exists public.source_label_map (
  domain text not null,
  url_like text,
  label text not null,
  unique nulls not distinct (domain, url_like)
);
alter table public.source_label_map enable row level security;
revoke all on public.source_label_map from anon, authenticated;

insert into public.source_label_map (domain, url_like, label) values
  ('165.g0v.tw', null, 'Taiwan 165 Anti-Fraud'),
  ('7674427.fs1.hubspotusercontent-na1.net', null, 'HubSpot file'),
  ('accel.com', null, 'Accel'),
  ('accessnewswire.com', null, 'ACCESS Newswire'),
  ('adamsstreetpartners.com', null, 'Adams Street Partners'),
  ('adviserinfo.sec.gov', null, 'SEC IAPD'),
  ('aflcio.org', null, 'AFL-CIO'),
  ('aft.org', null, 'AFT'),
  ('ajupress.com', null, 'Aju Press'),
  ('alternativeswatch.com', null, 'Alternatives Watch'),
  ('api.adviserinfo.sec.gov', null, 'SEC IAPD'),
  ('api.gleif.org', null, 'GLEIF'),
  ('arboralt.com', null, 'Arbor Alternatives'),
  ('archive.nytimes.com', null, 'The New York Times'),
  ('aumdb.com', null, 'AUMdb'),
  ('bafin.de', null, 'BaFin'),
  ('bamcornerpoint.com', null, 'BAM Cornerpoint'),
  ('bamfunds.com', null, 'BAM Funds'),
  ('bbc.com', null, 'BBC'),
  ('benefitsandpensionsmonitor.com', null, 'Benefits and Pensions Monitor'),
  ('blackstone.com', null, 'Blackstone'),
  ('blakeir.com', null, 'Blake IR'),
  ('bozemandailychronicle.com', null, 'Bozeman Daily Chronicle'),
  ('brokercheck.finra.org', null, 'FINRA BrokerCheck'),
  ('businessinsider.com', null, 'Business Insider'),
  ('bvp.com', null, 'Bessemer Venture Partners'),
  ('bylinetimes.com', null, 'Byline Times'),
  ('ca4.uscourts.gov', null, 'U.S. Court of Appeals, 4th Cir.'),
  ('calpers.ca.gov', null, 'CalPERS'),
  ('caproasia.com', null, 'Caproasia'),
  ('carolinajournal.com', null, 'Carolina Journal'),
  ('casedocs.omniagentsolutions.com', null, 'Omni Agent Solutions'),
  ('cases.justia.com', null, 'Justia'),
  ('cbsnews.com', null, 'CBS News'),
  ('cccera.gov', null, 'CCCERA'),
  ('cdn.arstechnica.net', null, 'Ars Technica'),
  ('cdn.mysfers.org', null, 'SFERS'),
  ('chicago.suntimes.com', null, 'Chicago Sun-Times'),
  ('claimdepot.com', null, 'ClaimDepot'),
  ('cnbc.com', null, 'CNBC'),
  ('coatue.com', null, 'Coatue'),
  ('courtconnect.courts.delaware.gov', null, 'Delaware Courts'),
  ('courthousenews.com', null, 'Courthouse News'),
  ('courtlistener.com', null, 'CourtListener'),
  ('courts.delaware.gov', null, 'Delaware Courts'),
  ('courts.ms.gov', null, 'Mississippi Courts'),
  ('creditorcoalition.org', null, 'Creditor Coalition'),
  ('crowdfundedwealth.com', null, 'Crowdfunded Wealth'),
  ('dailymail.com', null, 'Daily Mail'),
  ('dakota.com', null, 'Dakota'),
  ('decisiondepot.legal', null, 'Decision Depot'),
  ('divestoregon.org', null, 'Divest Oregon'),
  ('dk.usembassy.gov', null, 'U.S. Embassy Denmark'),
  ('docketalarm.com', null, 'Docket Alarm'),
  ('dpfp.org', null, 'Dallas Police & Fire Pension'),
  ('edgar.sec.gov', null, 'SEC EDGAR'),
  ('efts.sec.gov', null, 'SEC EDGAR'),
  ('einpresswire.com', null, 'EIN Presswire'),
  ('emeryreddy.com', null, 'Emery Reddy'),
  ('en.wikipedia.org', null, 'Wikipedia'),
  ('fa-mag.com', null, 'Financial Advisor'),
  ('files.adviserinfo.sec.gov', null, 'SEC IAPD'),
  ('finance.senate.gov', null, 'U.S. Senate Finance Committee'),
  ('finance.yahoo.com', null, 'Yahoo Finance'),
  ('finimize.com', null, 'Finimize'),
  ('finra.org', null, 'FINRA'),
  ('forbes.com', null, 'Forbes'),
  ('fortune.com', null, 'Fortune'),
  ('foundersfund.com', null, 'Founders Fund'),
  ('ftc.gov', null, 'FTC'),
  ('governance.enfield.gov.uk', null, 'Enfield Council'),
  ('govinfo.gov', null, 'GovInfo'),
  ('gt990datalake-rawdata.s3.amazonaws.com', null, 'IRS Form 990 (GivingTuesday)'),
  ('harmonyoswald.com', null, 'Harmony Oswald'),
  ('hedgeco.net', null, 'HedgeCo'),
  ('hedgefundalpha.com', null, 'Hedge Fund Alpha'),
  ('hedgeweek.com', null, 'Hedgeweek'),
  ('hig.com', null, 'H.I.G. Capital'),
  ('hoellbach.de', null, 'Höllbach'),
  ('horsleybridge.com', null, 'Horsley Bridge'),
  ('hottub.vc', null, 'Hot Tub VC'),
  ('hsgac.senate.gov', null, 'U.S. Senate HSGAC'),
  ('imrf.org', null, 'IMRF'),
  ('institutionalinvestor.com', null, 'Institutional Investor'),
  ('irei.com', null, 'IREI'),
  ('ironroadpartners.com', null, 'Iron Road Partners'),
  ('j-ic.co.jp', null, 'JIC'),
  ('jeffnewmanlaw.com', null, 'Jeff Newman Law'),
  ('jorgeschmidt.com', null, 'Jorge Schmidt'),
  ('jtcgroup.com', null, 'JTC Group'),
  ('justice.gov', null, 'U.S. DOJ'),
  ('khoslaventures.com', null, 'Khosla Ventures'),
  ('kleinerperkins.com', null, 'Kleiner Perkins'),
  ('kyret.ky.gov', null, 'Kentucky Retirement Systems'),
  ('labusinessjournal.com', null, 'Los Angeles Business Journal'),
  ('lacers.org', null, 'LACERS'),
  ('latimes.com', null, 'Los Angeles Times'),
  ('law.justia.com', null, 'Justia'),
  ('law360.com', null, 'Law360'),
  ('leagle.com', null, 'Leagle'),
  ('linkedin.com', null, 'LinkedIn'),
  ('lpm.org', null, 'Louisville Public Media'),
  ('mass.gov', null, 'Mass.gov'),
  ('mckinsey.com', null, 'McKinsey'),
  ('media.ca11.uscourts.gov', null, 'U.S. Court of Appeals, 11th Cir.'),
  ('meetings.boardbook.org', null, 'BoardBook'),
  ('michigan.gov', null, 'Michigan.gov'),
  ('missionlocal.org', null, 'Mission Local'),
  ('msbi.us', null, 'Minnesota SBI'),
  ('nasdaq.com', null, 'Nasdaq'),
  ('nctreasurer.gov', null, 'NC Treasurer'),
  ('nea.com', null, 'NEA'),
  ('news.bloomberglaw.com', null, 'Bloomberg Law'),
  ('news.crunchbase.com', null, 'Crunchbase News'),
  ('news.fintech.io', null, 'Fintech.io'),
  ('news.wttw.com', null, 'WTTW News'),
  ('newsletter.oldwell-labs.com', null, 'Oldwell Labs'),
  ('newswire.ca', null, 'Newswire.ca'),
  ('nic.nebraska.gov', null, 'Nebraska Investment Council'),
  ('nj.gov', null, 'New Jersey (nj.gov)'),
  ('npr.org', null, 'NPR'),
  ('nypost.com', null, 'New York Post'),
  ('nysb.uscourts.gov', null, 'U.S. Bankruptcy Court, S.D.N.Y.'),
  ('nystrs.org', null, 'NYSTRS'),
  ('observer.com', null, 'Observer'),
  ('ocers.org', null, 'OCERS'),
  ('ofsistorage.blob.core.windows.net', null, 'UK OFSI'),
  ('opalesque.com', null, 'Opalesque'),
  ('open.omb.delaware.gov', null, 'Delaware OMB'),
  ('oppler.ai', null, 'Oppler'),
  ('pa.gov', null, 'Pennsylvania (pa.gov)'),
  ('pacermonitor.com', null, 'PacerMonitor'),
  ('pitchbook.com', null, 'PitchBook'),
  ('planadviser.com', null, 'PLANADVISER'),
  ('prisonlegalnews.org', null, 'Prison Legal News'),
  ('privateequityinternational.com', null, 'Private Equity International'),
  ('privateequitywire.co.uk', null, 'Private Equity Wire'),
  ('prnewswire.com', null, 'PR Newswire'),
  ('projects.propublica.org', null, 'ProPublica'),
  ('prospect.org', null, 'The American Prospect'),
  ('realassets.ipe.com', null, 'IPE Real Assets'),
  ('regents.umich.edu', null, 'University of Michigan Regents'),
  ('reports.adviserinfo.sec.gov', null, 'SEC IAPD'),
  ('riamonitor.com', null, 'RIA Monitor'),
  ('rio.nd.gov', null, 'North Dakota RIO'),
  ('sali.com', null, 'SALI'),
  ('sbafla.com', null, 'Florida SBA'),
  ('seattle.gov', null, 'Seattle.gov'),
  ('sec.gov', null, 'SEC'),
  ('secondarylink.com', null, 'SecondaryLink'),
  ('senate.gov', null, 'U.S. Senate'),
  ('sethhettena.com', null, 'Seth Hettena'),
  ('sfexaminer.com', null, 'San Francisco Examiner'),
  ('sfrhctf.org', null, 'SF Retiree Health Care Trust'),
  ('shareholders.stepstonegroup.com', null, 'StepStone Group'),
  ('socialcounts.org', null, 'Social Counts'),
  ('statetreasurer.wyo.gov', null, 'Wyoming State Treasurer'),
  ('stepstonegroup.com', null, 'StepStone Group'),
  ('stocks.observer-reporter.com', null, 'Observer-Reporter'),
  ('stonepeak.com', null, 'Stonepeak'),
  ('storage.courtlistener.com', null, 'CourtListener'),
  ('techcrunch.com', null, 'TechCrunch'),
  ('telegraph.co.uk', null, 'The Telegraph'),
  ('tesladetroitderivativeaction.com', null, 'Tesla derivative action site'),
  ('theassemblync.com', null, 'The Assembly'),
  ('theguardian.com', null, 'The Guardian'),
  ('thenextweb.com', null, 'The Next Web'),
  ('thrivecap.com', null, 'Thrive Capital'),
  ('timesofindia.indiatimes.com', null, 'Times of India'),
  ('tmrs.com', null, 'TMRS'),
  ('transacted.io', null, 'Transacted'),
  ('treasury.ri.gov', null, 'Rhode Island Treasury'),
  ('trove.nakedcapitalism.com', null, 'Naked Capitalism'),
  ('trsil.org', null, 'TRS Illinois'),
  ('ucop.edu', null, 'University of California'),
  ('uky.edu', null, 'University of Kentucky'),
  ('unicourt.com', null, 'UniCourt'),
  ('wallethub.com', null, 'WalletHub'),
  ('warren.senate.gov', null, 'Sen. Elizabeth Warren'),
  ('wilshirelawfirm.com', null, 'Wilshire Law Firm'),
  ('wired.com', null, 'WIRED'),
  ('worthrises.org', null, 'Worth Rises'),
  ('www.sec.gov', null, 'SEC'),
  ('x.com', null, 'X'),
  ('yahoo.com', null, 'Yahoo'),
  ('ycombinator.com', null, 'Y Combinator'),
  ('sec.gov', '%sec.gov/%edgar%', 'SEC EDGAR'),
  ('sec.gov', '%sec.gov/Archives/%', 'SEC EDGAR')
on conflict (domain, url_like) do update set label = excluded.label;

create or replace function public.source_label(p_label text, p_url text)
 returns text language sql stable security definer set search_path to 'public'
as $f$
  select coalesce((
    select m.label from source_label_map m
     where lower(regexp_replace(btrim(p_label), '^www\.', '')) ~ '^[a-z0-9.-]+\.[a-z]{2,}$'
       and (lower(regexp_replace(btrim(p_label), '^www\.', '')) = m.domain or lower(regexp_replace(btrim(p_label), '^www\.', '')) like '%.' || m.domain)
       and (m.url_like is null or coalesce(p_url, '') ilike m.url_like)
     order by length(m.domain) desc, m.url_like is null
     limit 1), p_label)
$f$;
revoke all on function public.source_label(text, text) from public, anon, authenticated;

update public.fact_sources fs set label = source_label(fs.label, s.url)
  from public.sources s where s.id = fs.source_id and fs.label ~ '^[a-z0-9.-]+\.[a-z]{2,}$' and source_label(fs.label, s.url) <> fs.label;
update public.sources set publisher = source_label(publisher, url)
 where publisher ~ '^[a-z0-9.-]+\.[a-z]{2,}$' and source_label(publisher, url) <> publisher;

create or replace function public._src(p_type text, p_id uuid)
 returns jsonb language sql stable set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(jsonb_build_object('label', source_label(coalesce(fs.label, s.publisher), s.url), 'date', fs.date_label, 'url', s.url) order by fs.sort_order), '[]')
  from fact_sources fs join sources s on s.id = fs.source_id where fs.fact_type = p_type and fs.fact_id = p_id
$function$;

CREATE OR REPLACE FUNCTION public.firm_details(p_firm uuid)
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with f as (
    select x.*, x.value->>'field' fld,
      case when jsonb_typeof(x.value) = 'object' then x.value else jsonb_build_object('value', x.value) end v
    from vc_source_facts x
    where x.firm_id = p_firm and x.superseded_by is null and x.data_status::text in ('real','needs_proof')
      and x.value::text !~* '(different (person|people)|surname-only|name-only hit|name-order variant|not treated as a match|similar name)'
  ), r as (
    select f.*, case
      when fact_type = 'sanctions_check' and (fld in ('sanctions','sanctions_check') or v ? 'result') then 1
      when fld = 'terrorism_lists' then 2
      when fld = 'export_restrictions' then 3
      when fact_type = 'regulatory_record' and fld like 'regulatory_action%' or fld = 'sec_disciplinary'
        or (fact_type = 'legal_matter' and v->>'title' like '%DOJ%') then 4
      when fld in ('aml_penalties','adv_disclosures') then 5
      when fld = 'courts_worldwide' then 7
      when fld in ('registration_status','legal_entity') or fact_type in ('sec_crd','legal_entity') then 8
      when fld = 'people_screen' or (fact_type = 'legal_matter' and v->>'entity' like 'partner:%') then 9
      when fact_type = 'legal_matter' and (v ? 'title' or fld = 'legal_matter') then 6
      when fld = 'pep' then 10
    end rn,
    coalesce(v->>'title', v->>'value',
      case when v ? 'result' then 'Result: ' || replace(v->>'result','_',' ') || coalesce(' on ' || (select string_agg(e, ', ') from jsonb_array_elements_text(v->'lists') e), '')
        || coalesce(' · ' || (v->>'people_checked') || ' people checked', '') end,
      v::text) txt
    from f
  ), d as (
    select distinct on (rn, coalesce(v->>'detail', md5(txt))) * from r where rn is not null
    order by rn, coalesce(v->>'detail', md5(txt)), retrieved_at desc nulls last
  )
  select coalesce(json_agg(json_build_object('row', rn, 'facts', facts) order by rn), '[]'::json) from (
    select rn, json_agg(json_build_object('text', txt, 'case', v->>'detail', 'year', v->>'year', 'who', v->>'entity',
      'needs_proof', data_status::text = 'needs_proof', 'url', source_url, 'label', source_label(coalesce(source_label, v->>'publisher'), source_url),
      'date', to_char(retrieved_at, 'Mon FMDD, YYYY')) order by data_status::text, (v->>'year') desc nulls last, retrieved_at desc) facts
    from d group by rn) g
$function$;

CREATE OR REPLACE FUNCTION public._sec_items(p_key text, p_firm uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(it order by o), '[]') from (
    select jsonb_build_object('head', label || ': ' || value, 'label', label, 'value', value, 'src', _src('firm_profile_facts', id)) it, sort_order o
      from firm_profile_facts where firm_id = p_firm and section = p_key and p_key in ('overview', 'funds', 'lps')
    union all
    select jsonb_build_object('head', 'Check ' || n || ': ' || title, 'n', n, 'title', title, 'descr', descr, 'state', state, 'count', count_label, 'src', '[]'::jsonb), n
      from firm_check_rows where firm_id = p_firm and p_key = 'checks'
    union all
    select jsonb_build_object('head', title, 'grp', grp, 'year', year_label, 'role', role, 'state', state, 'status', status_label, 'tone', tone, 'note', note,
        'src', _src('firm_legal_items', id)), case grp when 'case' then 0 when 'regulator' then 1000 else 2000 end + sort_order
      from firm_legal_items where firm_id = p_firm and p_key = 'legal'
    union all
    select jsonb_build_object('head', p.headline, 'outlet', source_label(p.publisher, p.url), 'date', p.published_label, 'url', p.url, 'snippet', p.snippet, 'logo', p.logo_path, 'group', p.group_label,
        'src', jsonb_build_array(jsonb_build_object('label', source_label(p.publisher, p.url), 'date', p.published_label, 'url', p.url))), pf.sort_order
      from press_items p join press_item_firms pf on pf.press_item_id = p.id
      where pf.firm_id = p_firm and p_key = 'press' and p.data_status = 'real' and p.url <> ''
    union all
    select jsonb_build_object('head', headline, 'outlet', outlet, 'date', date_label, 'url', url, 'snippet', snippet, 'src', _src('founder_accounts', id)), sort_order
      from founder_accounts where firm_id = p_firm and p_key = 'founders'
    union all
    select jsonb_build_object('head', person_name, 'kind', kind, 'role', role, 'badge', badge, 'src', _src('firm_people_roles', id)),
        case kind when 'board' then 0 when 'move' then 1000 else 2000 end + sort_order
      from firm_people_roles where firm_id = p_firm and p_key = 'people'
    union all
    select jsonb_build_object('head', date_label || ' · ' || body, 'date', date_label, 'kind', kind, 'body', body, 'src', _src('timeline_events', id)), sort_order
      from timeline_events where firm_id = p_firm and p_key = 'timeline'
  ) x where p_key in ('checks', 'press') or jsonb_array_length(it->'src') > 0
$function$;
