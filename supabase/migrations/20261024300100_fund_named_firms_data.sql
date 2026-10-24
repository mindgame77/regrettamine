-- Pages named after a fund entity (GP / management company / fund number) instead of the firm, found 2026-10-24.
-- Each firm keeps one page with a long slug from its real name; the fund-numbered pages are merged into it (old slugs 301),
-- fund/legal names stay as aliases and are listed as fund entities. Name source per firm is in the comment and in
-- /workspace/backups/fund-named-firms-2026-10-24.csv. Backup: /workspace/backups/pre-fundname-2026-10-24/. Missing rows are skipped.

create temp table _fn_groups (keep text, members text[], new_slug text, display text, src text) on commit drop;
insert into _fn_groups values
  ('institutional-venture-management-xviii', array['institutional-venture-management-xviii']::text[], 'institutional-venture-partners', null, 'IAPD 324257 (Institutional Venture Management XVIII, Menlo Park) + ivp.com "IVP"'),
  ('aulis-capital-gp', array['aulis-capital-gp','aulis-capital-us']::text[], 'aulis-capital', 'Aulis Capital', 'IAPD 341185/341217 + auliscapital.com "Aulis Capital"'),
  ('biogeneration-iii-services', array['biogeneration-iii-services']::text[], 'biogeneration-ventures', 'BioGeneration Ventures', 'IAPD 327422 (BioGeneration Capital Funds III-V) + biogenerationventures.com'),
  ('blackhorn-ventures-3', array['blackhorn-ventures-3','blackhorn-ventures']::text[], 'blackhorn-ventures', null, 'IAPD 297981/325836 same Denver office + blackhornvc.com'),
  ('blue-moon-gp', array['blue-moon-gp']::text[], 'blue-moon-vc', 'Blue Moon VC', 'IAPD 314286 + blue-moon.vc "Blue Moon VC"'),
  ('braemar-capital-4', array['braemar-capital-4','braemar-capital']::text[], 'braemar-energy-ventures', 'Braemar Energy Ventures', 'IAPD 295525/295530 same NY office + braemarenergy.com "Braemar Energy Ventures"'),
  ('capital-midwest', array['capital-midwest','capital-midwest-3']::text[], 'capital-midwest-fund', 'Capital Midwest Fund', 'IAPD 282974/164385 (Mequon WI) + capitalmidwest.com "Capital Midwest Fund"'),
  ('draperdragon', array['draperdragon','draperdragon-management-company']::text[], 'draperdragon', null, 'IAPD 329183/320610 same San Mateo office'),
  ('dyne-ventures', array['dyne-ventures','dyne-ventures-3']::text[], 'dyne-ventures', null, 'IAPD 334897/340686 same West Palm Beach office'),
  ('eequity-3', array['eequity-3','eequity','eequity-4']::text[], 'eequity', null, 'eequity.se + EIF press release "eEquity AB"'),
  ('egarden-iv-capital', array['egarden-iv-capital','egarden-ii-capital','egarden-iii-capital']::text[], 'egarden-ventures', 'eGarden Ventures', 'IAPD 310599-310601 (Bank of America Tower HK) + HK Companies Registry eGarden Ventures; PitchBook eGarden Ventures same address'),
  ('fca-venture-partners', array['fca-venture-partners','fca-health-innovations','fca-venture-management-group']::text[], 'fca-venture-partners', 'FCA Venture Partners', 'IAPD 319570/319572/319574 same Nashville office + fcavp.com "FCA Venture Partners"'),
  ('fidelio-capital', array['fidelio-capital','fidelio-capital-3']::text[], 'fidelio-capital', null, 'Bolagsverket via allabolag (Fidelio Capital AB, Fidelio Capital II AB, Stockholm) + PEI profile "Fidelio Capital"'),
  ('founder-s-co-op', array['founder-s-co-op','founders-co-op-general-partner','founders-iv-general-partner']::text[], 'founders-co-op', 'Founders'' Co-op', 'IAPD 161880 lists Founders'' Co-op GP III and IV as relying advisers; 294007 other name Founders'' Co-op IV GP + founderscoop.com'),
  ('goldcrest-advisory', array['goldcrest-advisory','goldcrest']::text[], 'goldcrest-capital', 'Goldcrest Capital', 'IAPD 281506/339646 other name "Goldcrest Capital" + goldcrest.com'),
  ('headline-3', array['headline-3','headline']::text[], 'headline', null, 'IAPD 323221/319198 + headline.com "Headline"'),
  ('healthcap', array['healthcap','healthcap-4']::text[], 'healthcap', 'HealthCap', 'IAPD 305750/162464 same Stockholm office + healthcap.eu'),
  ('hpe-capital', array['hpe-capital']::text[], 'hauser-private-equity', 'Hauser Private Equity', 'IAPD 283607 other name "Hauser Private Equity" + hauserprivateequity.com'),
  ('icon-management-associates', array['icon-management-associates']::text[], 'icon-ventures', 'Icon Ventures', 'IAPD 286062 + iconventures.com "Icon Ventures"'),
  ('innovation-endeavors', array['innovation-endeavors','innovation-endeavors-4']::text[], 'innovation-endeavors', null, 'IAPD 288679/170740 same Palo Alto office + innovationendeavors.com'),
  ('innovation-works-development-3', array['innovation-works-development-3','innovation-works-development','sinovation','sinovation-hk-investment']::text[], 'sinovation-ventures', 'Sinovation Ventures', 'IAPD 162095/341819/341817/330180 + chuangxin.com (创新工场 = Sinovation Ventures, formerly Innovation Works)'),
  ('jstar', array['jstar','jstar-horizon-gp']::text[], 'jstar-capital', 'JSTAR Capital', 'IAPD 336372/336291 (Austin) + jstarinvestments.com "JSTAR Capital"'),
  ('kuos-investment', array['kuos-investment']::text[], 'uphonest-capital', 'UpHonest Capital', 'IAPD 289165 ADV website uphonestcapital.com; SEC Form D filings (Wei Guo)'),
  ('lever-vc-fund-ii-technical', array['lever-vc-fund-ii-technical']::text[], 'lever-vc', 'Lever VC', 'IAPD 324666 + levervc.com "Lever VC"'),
  ('long-river-capital', array['long-river-capital']::text[], 'lrvhealth', 'LRVHealth', 'IAPD 162448 (Long River Capital Mgmt, Boston) + lrvhealth.com'),
  ('makers-investment-advisor-ii-us', array['makers-investment-advisor-ii-us','makers-investment-advisor-ii-sg']::text[], 'makers-fund', 'Makers Fund', 'IAPD 313324/321127 (other name "Makers") + makersfund.com "Makers Fund"'),
  ('pathlight', array['pathlight','pathlight-3','pathlight-4']::text[], 'pathlight', null, 'IAPD 343937/327069/322180 same Old Bridge office + pathlight.vc'),
  ('pearl-energy-investment-management-iii', array['pearl-energy-investment-management-iii','pearl-energy-investment']::text[], 'pearl-energy-investments', 'Pearl Energy Investments', 'IAPD 323917/281120 same Dallas office + pearl-energy.com'),
  ('prolog-ventures-hl', array['prolog-ventures-hl']::text[], 'prolog-ventures', 'Prolog Ventures', 'IAPD 170338 other name Prolog Ventures IV + prologventures.com'),
  ('razor-s-edge-ventures', array['razor-s-edge-ventures','razor-s-edge-ventures-3','razor-s-edge-gp']::text[], 'razor-s-edge-ventures', null, 'IAPD 319605/297288/333731 same Reston office'),
  ('seed-capital-denmark', array['seed-capital-denmark','seed-capital-management-iii-i-s','seed-capital-management-iv-i-s']::text[], 'seed-capital-denmark', null, 'Danish CVR 37140279 / 41370629 annual reports: management companies of Seed Capital Denmark III/IV K/S + seedcapital.dk'),
  ('sequoia-capital-iv-israel', array['sequoia-capital-iv-israel']::text[], 'sequoia-capital-israel', 'Sequoia Capital Israel', 'IAPD 161213 other name "Sequoia Capital Israel IV"; firm brand Sequoia Capital Israel'),
  ('sigma-management-6', array['sigma-management-6']::text[], 'sigma-partners', 'Sigma Partners', 'IAPD 160560 other name "Sigma Partners" + sigmapartners.com'),
  ('sierra-ventures-management-iii', array['sierra-ventures-management-iii']::text[], 'sierra-ventures', null, 'IAPD 163849 Sierra Ventures Management III; display already Sierra Ventures'),
  ('spintop', array['spintop','spintop-3']::text[], 'spintop-ventures', 'Spintop Ventures', 'spintopventures.com + EIF press release "Spintop Ventures" Fund IV; Crunchbase'),
  ('stellaris', array['stellaris','stellaris-investment-management-3-ifsc','stellaris-venture-advisors-2']::text[], 'stellaris-venture-partners', 'Stellaris Venture Partners', 'IAPD 322270/321091/338844 + stellarisvp.com "Stellaris Venture Partners"'),
  ('threshold-ventures', array['threshold-ventures','threshold-ventures-ii','threshold-management']::text[], 'threshold-ventures', null, 'IAPD 326413/326501/305977 same Palo Alto office + threshold.vc'),
  ('toba-capital', array['toba-capital','toba-capital-fund-i-series','toba-capital-fund-ii-series']::text[], 'toba-capital', null, 'IAPD 169815/169803 "a series of Toba Capital LLC" + tobacapital.com'),
  ('true-equity-3', array['true-equity-3','true-equity']::text[], 'true-equity', null, 'IAPD 328219/313330 same Yarmouth office'),
  ('vesalius-biocapital-iii-partners', array['vesalius-biocapital-iii-partners','vesalius-biocapital-iv-partners']::text[], 'vesalius-biocapital', 'Vesalius Biocapital', 'Luxembourg RCS B213130 + vesaliusbiocapital-3.com "Vesalius Biocapital"'),
  ('viola-ventures-v-c-management-4', array['viola-ventures-v-c-management-4','viola-ventures-v-c-management-3','viola-ventures-management-2017-limited-partnership','viola-ventures-management-services-vii-limited-partnership','viola-ventures-6-management-services-limited-partnership','viola-ventures-conviction']::text[], 'viola-ventures', 'Viola Ventures', 'IAPD 295204/295197/295217/341600/313980/339067 same Tel Aviv office + viola.vc "Viola Ventures"'),
  ('vision-plus-capital-international', array['vision-plus-capital-international']::text[], 'vision-plus-capital', 'Vision Plus Capital', 'IAPD 290222 + visionpluscapital.com (元璟资本 Vision Plus Capital)'),
  ('atlantic-bridge-4', array['atlantic-bridge-4','atlantic-bridge','atlantic-bridge-3']::text[], 'atlantic-bridge', null, 'Central Bank of Ireland register (Atlantic Bridge III/IV GP Ltd, 22 Fitzwilliam Sq) + abven.com "Atlantic Bridge"'),
  ('gcp-management-2015', array['gcp-management-2015']::text[], 'glilot-capital-partners', 'Glilot Capital Partners', 'IAPD 298148 + glilotcapital.com "Glilot Capital"'),
  ('fairview-capital-partners', array['fairview-capital-partners','fairview-constitution']::text[], 'fairview-capital-partners', null, 'IAPD 159304 (Fairview Constitution Management IV, West Hartford CT; affiliate Fairview Capital Partners) + fairviewcapital.com');

-- fund entities and legal names from every page in a group, recorded on the kept page before merging (no invented data)
insert into public.fund_entities (firm_id, name, entity_kind, crd, notes, data_status)
select k.id, m.legal_name, 'gp_or_manager', nullif(m.sec_crd, ''), 'legal name of former page /vc/' || m.slug || '/; name source: ' || g.src, k.data_status
from _fn_groups g
join public.firms k on k.slug = g.keep and k.deleted_at is null
join public.firms m on m.slug = any(g.members) and m.deleted_at is null
where nullif(btrim(m.legal_name), '') is not null
  and lower(m.legal_name) <> lower(coalesce(g.display, k.display_name, k.name))
  and not exists (select 1 from public.fund_entities e where e.firm_id = k.id and lower(e.name) = lower(m.legal_name));

insert into public.firm_aliases (firm_id, alias, source)
select k.id, k.legal_name, 'sec_legal' from _fn_groups g join public.firms k on k.slug = g.keep and k.deleted_at is null
where nullif(btrim(k.legal_name), '') is not null and lower(k.legal_name) <> lower(coalesce(g.display, k.display_name, k.name))
on conflict do nothing;

select public.merge_firms(g.keep, d, 'fund-named page 2026-10-24') from _fn_groups g, unnest(g.members) d where d <> g.keep;
select public.rename_firm_slug(g.keep, g.new_slug, g.display, 'fund-named page 2026-10-24') from _fn_groups g;
