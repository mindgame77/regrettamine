-- Pages named after a fund entity (GP / management company / fund number) instead of the firm, found 2026-10-24 (second pass on the rows skipped in 20261024300100).
-- Each firm keeps one page with a long slug from its real name; the fund-numbered pages are merged into it (old slugs 301),
-- fund/legal names stay as aliases and are listed as fund entities. Name source per firm is in the comment and in
-- /workspace/backups/fund-named-firms-2026-10-24.csv. Backup: /workspace/backups/pre-fundname2-2026-10-24/. Missing rows are skipped.

create temp table _fn2_groups (keep text, members text[], new_slug text, display text, src text) on commit drop;
insert into _fn2_groups values
  ('sorenson-capital', array['sorenson-capital','west-rim-capital-associates-ii','west-rim-ii-ugp']::text[], 'sorenson-capital', null, 'IAPD 145085/339904 ADV website sorensoncapital.com, LinkedIn sorenson-capital, funds Sorenson Capital Partners, affiliates Sorenson Ventures; PR Newswire 2017: Sorenson Ventures is a group within Sorenson Capital; sorensonventures.com 301s to sorensoncapital.com'),
  ('hcv', array['hcv']::text[], 'healthcare-ventures', 'HealthCare Ventures', 'IAPD 163510 ADV website hcven.com, funds HealthCare Ventures VIII/IX'),
  ('cnl', array['cnl']::text[], 'cnl-financial-group', 'CNL Financial Group', 'IAPD 174178 affiliates CNL Financial Group / CNL Strategic Capital; Form D CNL Strategic Venture Partners (indirectly controlled by CNL Financial Group)'),
  ('allegis-capital', array['allegis-capital','cip-ii-administrative','mediatech-administrative']::text[], 'allegis-capital', null, 'IAPD 301595/301637 ADV websites allegiscapital.com / allegiscyber.com, affiliate Allegis Capital Management Company'),
  ('stratus-gestao-de-carteiras-ltda', array['stratus-gestao-de-carteiras-ltda','stratus-capital-partners-iii-s','scp-s']::text[], 'stratus-group', 'Stratus Group', 'IAPD 302079/281361/281371 ADV website stratusbr.com, LinkedIn stratus-group; PEI profile "Stratus Group"; IDB Invest Stratus Capital Partners III'),
  ('bluebird-ventures-gp', array['bluebird-ventures-gp']::text[], 'bluebird-ventures', 'Bluebird Ventures', 'IAPD 304804 ADV website bluebirdvc.com, fund Bluebird Ventures I'),
  ('biotrack', array['biotrack']::text[], 'biotrack-capital', 'BioTrack Capital', 'IAPD 305488 affiliates BioTrack Capital Management Ltd; PitchBook/Form D BioTrack Capital Fund I/II; Tracxn BioTrack Capital'),
  ('agp', array['agp','agp-3']::text[], 'aegis-group-partners', 'Aegis Group Partners', 'IAPD 310477/310478 (NYC) funds IP Successor Fund 21 / Celestial Successor Fund; PitchBook: IP Successor Fund 21 managed by Aegis Group Partners, New York'),
  ('north-coast-ventures', array['north-coast-ventures','ncaf']::text[], 'north-coast-ventures', null, 'IAPD 311015 ADV website northcoast.vc, funds North Coast Angel Fund II-IV, affiliate North Coast Ventures Management'),
  ('sbva', array['sbva','sv-investment']::text[], 'sbva', 'SBVA', 'IAPD 312011 affiliates SBVA Corp / SBVA Capital Holdings; SEC 13G/Form D China Ventures Fund (GP SV GP I, ultimate parent SoftBank Ventures Asia = SBVA)'),
  ('eminence-marvelous-gp', array['eminence-marvelous-gp']::text[], 'eminence-ventures', 'Eminence Ventures', 'IAPD 313468 ADV website emventures.cn, LinkedIn "Eminence Ventures 靖亚资本", fund Eminence China Enterprise Fund II'),
  ('yu-galaxy', array['yu-galaxy','yu-star']::text[], 'yu-galaxy', null, 'IAPD 318251 (Palo Alto) fund Yu Star Fund I; PitchBook: Yu Star Fund I managed by Yu Galaxy (yugalaxy.com); Form D related person Pingrong Yu'),
  ('mgc-venture-partners', array['mgc-venture-partners','mgp-venture']::text[], 'mountain-group-partners', 'Mountain Group Partners', 'IAPD 318455/298455 ADV website mtngp.com, LinkedIn mountain-group-partners'),
  ('viola-ventures', array['viola-ventures','viola-opportunity-management-fund-1-limited-partnership']::text[], 'viola-ventures', null, 'IAPD 319245 ADV website viola-group.com, related advisers are Viola Ventures entities; Radient/AUM13F Viola Opportunity I'),
  ('runtide-capital', array['runtide-capital','runtide-capital-spv']::text[], 'runtide-capital', null, 'IAPD 320744 ADV website runtidecapital.com; same firm as IAPD 307164 Runtide Capital'),
  ('ncn-management-company', array['ncn-management-company','ncn-management-company-pf']::text[], 'nashville-capital-network', 'Nashville Capital Network', 'IAPD 321890/289601 ADV website nashvillecapital.com "Nashville Capital Network"'),
  ('trium-ventures-gp', array['trium-ventures-gp']::text[], 'trium-group', 'The Trium Group', 'IAPD 322206 (909 Montgomery St SF); PitchBook: Trium Venture Partners I managed by The Trium Group (triumgroup.com, same address); Form D related persons Darren Gold, Andrew Blum'),
  ('hlc-vgc-management-iv', array['hlc-vgc-management-iv']::text[], 'highlight-capital', 'HighLight Capital', 'IAPD 323435 ADV website hlcfund.com; hlcfund.com "HighLight Capital" (弘晖资本); LinkedIn highlight-capital'),
  ('grove', array['grove','mata-technologies-ventures-iii-2021']::text[], 'grove-ventures', 'Grove Ventures', 'IAPD 324050 ADV website grovevc.com, funds Grove Ventures; grovevc.com "Grove Ventures"'),
  ('sabi', array['sabi']::text[], 'sabi-fund', 'SABI Fund', 'IAPD 326511 fund SABI Fund I; SEC Form D "SABI Fund I - SABI Fund LP"; Startup Intros profile "Sabi Fund"'),
  ('greenfield-cities-2', array['greenfield-cities-2','greenfield-cities']::text[], 'greenfield-partners', 'Greenfield Partners', 'IAPD 328032/309322 ADV website greenfield-growth.com, funds Greenfield Partners, affiliate Greenfield Cities LLC'),
  ('razor-gp-2', array['razor-gp-2','razor-aptos']::text[], 'razor-capital', 'Razor Capital', 'IAPD 332108/332107 (Dubai, managing member Abhinav Munshi); razorcapital.net About Us: Abhinav Munshi co-founder of Razor Capital'),
  ('magic-stone-alternative-private-equity', array['magic-stone-alternative-private-equity','msa-china']::text[], 'msa-capital', 'MSA Capital', 'IAPD 332202/335450 ADV website msacap.com "MSA Capital"'),
  ('igah-gestora-ltda', array['igah-gestora-ltda','pevc-i-general-partner']::text[], 'igah-ventures', 'Igah Ventures', 'IAPD 332786/317507 fund Igah Ventures IV, affiliate IGAH Gestora; SEC Form D Igah Ventures IV LP; Startup Intros "Igah Ventures"'),
  ('second-century-ventures-gp', array['second-century-ventures-gp']::text[], 'second-century-ventures', 'Second Century Ventures', 'IAPD 333148 (430 N Michigan Ave Chicago); nar.realtor and scv.vc "Second Century Ventures" (NAR)'),
  ('flywheel', array['flywheel']::text[], 'flywheel-fund', 'Flywheel Fund', 'IAPD 338946 (Bloomington IN) fund Flywheel Fund VI; SEC Form D related person Eric Steele; flywheelfund.vc "Flywheel Fund"; Inside Indiana Business'),
  ('startup-capital-ventures-management-co', array['startup-capital-ventures-management-co']::text[], 'startup-capital-ventures', 'Startup Capital Ventures', 'IAPD 341911 ADV websites startupcv.com / scv-sbi.com; startupcv.com "Startup Capital Ventures"'),
  ('capstar-ventures', array['capstar-ventures','wxyz']::text[], 'capstar-ventures', null, 'IAPD 342237 ADV websites capstar.vc / capstarventures.com, affiliates Capstar Ventures GP'),
  ('alder-iii-d', array['alder-iii-d']::text[], 'alder', 'Alder', 'Finansinspektionen EuVECA register (Alder III (D) AB); alder.se "Alder completes closing of Alder III"'),
  ('atlantic-bridge', array['atlantic-bridge','atlantic-bridge-innovation','atlantic-bridge-early-stage']::text[], 'atlantic-bridge', null, 'Irish CRO 774502 / CBI EuVECA register: Atlantic Bridge Innovation III GP Ltd at 22 Fitzwilliam Sq (Atlantic Bridge); EuVECA register Atlantic Bridge Early Stage GP Ltd'),
  ('ballista-capital-spv', array['ballista-capital-spv','ballista-capital-spv-3']::text[], 'ballista-capital', 'Ballista Capital', 'Bolagsverket via allabolag/Syna (Ballista Capital SPV AB, Stockholm) + ballistacapital.se "Om Ballista"'),
  ('consolid-equity-iii-d', array['consolid-equity-iii-d','consolid-equity-iii-e']::text[], 'consolid-equity', 'Consolid Equity', 'Bolagsverket via merinfo (Consolid Equity III (E) AB) + consolid.se + PEI profile "Consolid Equity"; Vinge press release'),
  ('forbion', array['forbion','fcpm-iii-services']::text[], 'forbion', null, 'Dutch KvK 56419899 via GLEIF/Bloomberg LEI + CNMV register: FCPM III Services B.V. (Naarden) manages Forbion funds'),
  ('gen-ii-management-company-luxembourg', array['gen-ii-management-company-luxembourg']::text[], 'gen-ii-fund-services', 'Gen II Fund Services', 'FSMA register + gen2fund.com group entities: Gen II Management Company (Luxembourg) is Gen II Fund Services (fund administrator / AIFM)'),
  ('ncp-ivs-iii-gp-aps', array['ncp-ivs-iii-gp-aps']::text[], 'northcap-partners', 'NorthCap Partners', 'Danish CVR 33373104 (directors Kim Wiencken, Thomas Weilby Knudsen) + northcap.vc team page + PEI profile "NorthCap Partners"'),
  ('never-eat-alone-general-partners', array['never-eat-alone-general-partners']::text[], 'nea-partners', 'NEA Partners', 'Bolagsverket via Bolagsradar (Never Eat Alone General Partners III AB) + FI EuVECA register + neapartners.se "NEA Partners"'),
  ('odewald-kmu-iii-gesellschaft-fur-beteiligungen-mbh', array['odewald-kmu-iii-gesellschaft-fur-beteiligungen-mbh']::text[], 'odewald-kmu', 'Odewald KMU', 'Handelsregister Berlin via OpenRegister + EuVECA register + odewaldkmu.com "Odewald KMU"'),
  ('oltre-impact-societa-di-gestione-del-risparmio-spa-gestore-euveca', array['oltre-impact-societa-di-gestione-del-risparmio-spa-gestore-euveca','oltre-ii-sicaf-euveca-spa']::text[], 'oltre-impact', 'Oltre Impact', 'oltreimpact.com: Oltre II SICAF EuVECA is managed by Oltre Impact SGR (formerly Oltre Venture); EIF/Fondo Italiano press release'),
  ('procuritas-capital-investors-vii-d', array['procuritas-capital-investors-vii-d']::text[], 'procuritas', 'Procuritas', 'FI EuVECA register (Procuritas Capital Investors VII (D) AB) + procuritas.com "PCI VII"'),
  ('stoaf-iii-venture-partners', array['stoaf-iii-venture-partners']::text[], 'stoaf', 'STOAF', 'Bolagsverket via allabolag/Syna (STOAF III Venture Partners AB, Stockholm) + stoaf.se'),
  ('3ts-capital-partners', array['3ts-capital-partners','tcee']::text[], '3ts-capital-partners', null, 'Luxembourg RCS B240552 via North Data: TCEE Fund IV GP Sàrl shareholder/adviser 3TS Capital Partners; 3tscapital.com SFDR disclosure'),
  ('v-bio-management-2', array['v-bio-management-2']::text[], 'v-bio-ventures', 'V-Bio Ventures', 'Belgian KBO 0758.543.760 (V-Bio Management 2, Gent) manages V-Bio Fund 2; v-bio.ventures press release'),
  ('yield-lab-europe-fund-1', array['yield-lab-europe-fund-1']::text[], 'yield-lab-europe', 'Yield Lab Europe', 'gov.ie / Enterprise Ireland press release + theyieldlab.eu SFDR (Yield Lab Europe Fund 1)');


-- fund entities and legal names from every page in a group, recorded on the kept page before merging (no invented data)
insert into public.fund_entities (firm_id, name, entity_kind, crd, notes, data_status)
select k.id, m.legal_name, 'gp_or_manager', nullif(m.sec_crd, ''), 'legal name of former page /vc/' || m.slug || '/; name source: ' || g.src, k.data_status
from _fn2_groups g
join public.firms k on k.slug = g.keep and k.deleted_at is null
join public.firms m on m.slug = any(g.members) and m.deleted_at is null
where nullif(btrim(m.legal_name), '') is not null
  and lower(m.legal_name) <> lower(coalesce(g.display, k.display_name, k.name))
  and not exists (select 1 from public.fund_entities e where e.firm_id = k.id and lower(e.name) = lower(m.legal_name));

insert into public.firm_aliases (firm_id, alias, source)
select k.id, k.legal_name, 'sec_legal' from _fn2_groups g join public.firms k on k.slug = g.keep and k.deleted_at is null
where nullif(btrim(k.legal_name), '') is not null and lower(k.legal_name) <> lower(coalesce(g.display, k.display_name, k.name))
on conflict do nothing;

select public.merge_firms(g.keep, d, 'fund-named page 2026-10-24 (pass 2)') from _fn2_groups g, unnest(g.members) d where d <> g.keep;
select public.rename_firm_slug(g.keep, g.new_slug, g.display, 'fund-named page 2026-10-24 (pass 2)') from _fn2_groups g;

-- sorensonventures.com 301s to sorensoncapital.com, the website both West Rim ADVs list
update public.firms set primary_domain = 'sorensoncapital.com'
where slug = 'sorenson-capital' and deleted_at is null and primary_domain = 'sorensonventures.com';
