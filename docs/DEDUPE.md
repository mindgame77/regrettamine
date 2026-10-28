> Dated record, not the rulebook. The only rules are in [docs/PAGE_DATA_GUIDE.md](PAGE_DATA_GUIDE.md). Where this file disagrees with that guide, the guide wins.

# Duplicate firm pages

* `merge_firms(p_keep, p_drop, p_reason)` (service role, slugs): keeps `p_keep`, soft-deletes `p_drop` (deleted_at,
  unpublished, not indexable), records `firm_slug_redirects(old_slug → new_slug)` (re-pointing older redirects), adds the
  dropped page's names as `firm_aliases` (source `merged`) so search still finds them, sets the dropped `research_queue`
  entry `duplicate_of = keep` (new research lands on the survivor), and moves saved-firm (watchlist) rows.
  Raw research submissions are untouched.
* `firm_redirect(slug)` (anon): used by the /vc/ edge when a slug has no page. Follows redirect rows (max 5 hops) to a
  live page; otherwise matches the slug as a name (`sequoia-capital` → name/display/short name/alias key) and returns a
  slug only for an unambiguous match. The edge answers **301** to `/vc/<slug>/` (or `/full/`), else 404.
* `firm_duplicate_candidates` (service role): pages that look like the same firm, for review.
* Survivor choice: launch page, then indexable, then most scans, then watchers/jobs, then having a CRD.
* Oct 24, 2026 merge: `supabase/migrations/20261024280100_merge_duplicates_data.sql` (62 pages into 48 survivors).
  Backup before applying: `/workspace/backups/pre-dedupe-2026-10-24/` on the ops box.

## Fund-named pages (2026-10-24)

Pages named after a fund entity (GP, management company, `Fund III`, `Management 6`...) instead of the firm. Each firm now has one page with a long slug from its real name (`/vc/institutional-venture-partners/`, never short forms). The fund-numbered pages were merged with `merge_firms`, and the survivor was renamed with `rename_firm_slug(old, new, display)` (`20261024300000_rename_firm_slug.sql`). Every old slug 301s. Legal and fund names are kept as aliases (`sec_legal`, `previous_display`, `merged`) and as `fund_entities` rows on the kept page. Data: `20261024300100_fund_named_firms_data.sql`. Backup: `/workspace/backups/pre-fundname-2026-10-24/`. Per-row name source: `fund-named-firms-2026-10-24.csv`.

Not changed (no reliable source for the firm name yet, or a false match like Atom XVII): listed in the CSV as `skipped - low confidence`.

| New page | Merged / renamed from | Name source |
|---|---|---|
| `institutional-venture-partners` | `institutional-venture-management-xviii` | IAPD 324257 (Institutional Venture Management XVIII, Menlo Park) + ivp.com "IVP" |
| `aulis-capital` | `aulis-capital-gp`, `aulis-capital-us` | IAPD 341185/341217 + auliscapital.com "Aulis Capital" |
| `biogeneration-ventures` | `biogeneration-iii-services` | IAPD 327422 (BioGeneration Capital Funds III-V) + biogenerationventures.com |
| `blackhorn-ventures` | `blackhorn-ventures-3` | IAPD 297981/325836 same Denver office + blackhornvc.com |
| `blue-moon-vc` | `blue-moon-gp` | IAPD 314286 + blue-moon.vc "Blue Moon VC" |
| `braemar-energy-ventures` | `braemar-capital-4`, `braemar-capital` | IAPD 295525/295530 same NY office + braemarenergy.com "Braemar Energy Ventures" |
| `capital-midwest-fund` | `capital-midwest`, `capital-midwest-3` | IAPD 282974/164385 (Mequon WI) + capitalmidwest.com "Capital Midwest Fund" |
| `draperdragon` | `draperdragon-management-company` | IAPD 329183/320610 same San Mateo office |
| `dyne-ventures` | `dyne-ventures-3` | IAPD 334897/340686 same West Palm Beach office |
| `eequity` | `eequity-3`, `eequity-4` | eequity.se + EIF press release "eEquity AB" |
| `egarden-ventures` | `egarden-iv-capital`, `egarden-ii-capital`, `egarden-iii-capital` | IAPD 310599-310601 (Bank of America Tower HK) + HK Companies Registry eGarden Ventures; PitchBook eGarden Ventures same address |
| `fca-venture-partners` | `fca-health-innovations`, `fca-venture-management-group` | IAPD 319570/319572/319574 same Nashville office + fcavp.com "FCA Venture Partners" |
| `fidelio-capital` | `fidelio-capital-3` | Bolagsverket via allabolag (Fidelio Capital AB, Fidelio Capital II AB, Stockholm) + PEI profile "Fidelio Capital" |
| `founders-co-op` | `founder-s-co-op`, `founders-co-op-general-partner`, `founders-iv-general-partner` | IAPD 161880 lists Founders' Co-op GP III and IV as relying advisers; 294007 other name Founders' Co-op IV GP + founderscoop.com |
| `goldcrest-capital` | `goldcrest-advisory`, `goldcrest` | IAPD 281506/339646 other name "Goldcrest Capital" + goldcrest.com |
| `headline` | `headline-3` | IAPD 323221/319198 + headline.com "Headline" |
| `healthcap` | `healthcap-4` | IAPD 305750/162464 same Stockholm office + healthcap.eu |
| `hauser-private-equity` | `hpe-capital` | IAPD 283607 other name "Hauser Private Equity" + hauserprivateequity.com |
| `icon-ventures` | `icon-management-associates` | IAPD 286062 + iconventures.com "Icon Ventures" |
| `innovation-endeavors` | `innovation-endeavors-4` | IAPD 288679/170740 same Palo Alto office + innovationendeavors.com |
| `sinovation-ventures` | `innovation-works-development-3`, `innovation-works-development`, `sinovation`, `sinovation-hk-investment` | IAPD 162095/341819/341817/330180 + chuangxin.com (创新工场 = Sinovation Ventures, formerly Innovation Works) |
| `jstar-capital` | `jstar`, `jstar-horizon-gp` | IAPD 336372/336291 (Austin) + jstarinvestments.com "JSTAR Capital" |
| `uphonest-capital` | `kuos-investment` | IAPD 289165 ADV website uphonestcapital.com; SEC Form D filings (Wei Guo) |
| `lever-vc` | `lever-vc-fund-ii-technical` | IAPD 324666 + levervc.com "Lever VC" |
| `lrvhealth` | `long-river-capital` | IAPD 162448 (Long River Capital Mgmt, Boston) + lrvhealth.com |
| `makers-fund` | `makers-investment-advisor-ii-us`, `makers-investment-advisor-ii-sg` | IAPD 313324/321127 (other name "Makers") + makersfund.com "Makers Fund" |
| `pathlight` | `pathlight-3`, `pathlight-4` | IAPD 343937/327069/322180 same Old Bridge office + pathlight.vc |
| `pearl-energy-investments` | `pearl-energy-investment-management-iii`, `pearl-energy-investment` | IAPD 323917/281120 same Dallas office + pearl-energy.com |
| `prolog-ventures` | `prolog-ventures-hl` | IAPD 170338 other name Prolog Ventures IV + prologventures.com |
| `razor-s-edge-ventures` | `razor-s-edge-ventures-3`, `razor-s-edge-gp` | IAPD 319605/297288/333731 same Reston office |
| `seed-capital-denmark` | `seed-capital-management-iii-i-s`, `seed-capital-management-iv-i-s` | Danish CVR 37140279 / 41370629 annual reports: management companies of Seed Capital Denmark III/IV K/S + seedcapital.dk |
| `sequoia-capital-israel` | `sequoia-capital-iv-israel` | IAPD 161213 other name "Sequoia Capital Israel IV"; firm brand Sequoia Capital Israel |
| `sigma-partners` | `sigma-management-6` | IAPD 160560 other name "Sigma Partners" + sigmapartners.com |
| `sierra-ventures` | `sierra-ventures-management-iii` | IAPD 163849 Sierra Ventures Management III; display already Sierra Ventures |
| `spintop-ventures` | `spintop`, `spintop-3` | spintopventures.com + EIF press release "Spintop Ventures" Fund IV; Crunchbase |
| `stellaris-venture-partners` | `stellaris`, `stellaris-investment-management-3-ifsc`, `stellaris-venture-advisors-2` | IAPD 322270/321091/338844 + stellarisvp.com "Stellaris Venture Partners" |
| `threshold-ventures` | `threshold-ventures-ii`, `threshold-management` | IAPD 326413/326501/305977 same Palo Alto office + threshold.vc |
| `toba-capital` | `toba-capital-fund-i-series`, `toba-capital-fund-ii-series` | IAPD 169815/169803 "a series of Toba Capital LLC" + tobacapital.com |
| `true-equity` | `true-equity-3` | IAPD 328219/313330 same Yarmouth office |
| `vesalius-biocapital` | `vesalius-biocapital-iii-partners`, `vesalius-biocapital-iv-partners` | Luxembourg RCS B213130 + vesaliusbiocapital-3.com "Vesalius Biocapital" |
| `viola-ventures` | `viola-ventures-v-c-management-4`, `viola-ventures-v-c-management-3`, `viola-ventures-management-2017-limited-partnership`, `viola-ventures-management-services-vii-limited-partnership`, `viola-ventures-6-management-services-limited-partnership`, `viola-ventures-conviction` | IAPD 295204/295197/295217/341600/313980/339067 same Tel Aviv office + viola.vc "Viola Ventures" |
| `vision-plus-capital` | `vision-plus-capital-international` | IAPD 290222 + visionpluscapital.com (元璟资本 Vision Plus Capital) |
| `atlantic-bridge` | `atlantic-bridge-4`, `atlantic-bridge-3` | Central Bank of Ireland register (Atlantic Bridge III/IV GP Ltd, 22 Fitzwilliam Sq) + abven.com "Atlantic Bridge" |
| `glilot-capital-partners` | `gcp-management-2015` | IAPD 298148 + glilotcapital.com "Glilot Capital" |
| `fairview-capital-partners` | `fairview-constitution` | IAPD 159304 (Fairview Constitution Management IV, West Hartford CT; affiliate Fairview Capital Partners) + fairviewcapital.com |


### Second pass on skipped rows (2026-10-24)

All 47 rows skipped in the first pass now have a confirmed firm name (SEC IAPD/ADV, Form D, national registries, firm websites, PitchBook, press). Same method: merge_firms + rename_firm_slug, old slugs 301, legal names kept as aliases and fund entities. Related fund-named pages of the same firm (same ADV website or registry link) were merged in too. Migration `20261024310000_fund_named_firms_pass2.sql`; backup `/workspace/backups/pre-fundname2-2026-10-24/`. `sorenson-capital` primary domain set to sorensoncapital.com (sorensonventures.com 301s there). No rows remain skipped.

| Page | Merged / renamed from | Name source |
|---|---|---|
| `sorenson-capital` | `west-rim-capital-associates-ii`, `west-rim-ii-ugp` | IAPD 145085/339904 ADV website sorensoncapital.com, LinkedIn sorenson-capital, funds Sorenson Capital Partners, affiliates Sorenson Ventures; PR Newswire 2017: Sorenson Ventures is a group within Sorenson Capital; sorensonventures.com 301s to sorensoncapital.com |
| `healthcare-ventures` | `hcv` | IAPD 163510 ADV website hcven.com, funds HealthCare Ventures VIII/IX |
| `cnl-financial-group` | `cnl` | IAPD 174178 affiliates CNL Financial Group / CNL Strategic Capital; Form D CNL Strategic Venture Partners (indirectly controlled by CNL Financial Group) |
| `allegis-capital` | `cip-ii-administrative`, `mediatech-administrative` | IAPD 301595/301637 ADV websites allegiscapital.com / allegiscyber.com, affiliate Allegis Capital Management Company |
| `stratus-group` | `stratus-gestao-de-carteiras-ltda`, `stratus-capital-partners-iii-s`, `scp-s` | IAPD 302079/281361/281371 ADV website stratusbr.com, LinkedIn stratus-group; PEI profile "Stratus Group"; IDB Invest Stratus Capital Partners III |
| `bluebird-ventures` | `bluebird-ventures-gp` | IAPD 304804 ADV website bluebirdvc.com, fund Bluebird Ventures I |
| `biotrack-capital` | `biotrack` | IAPD 305488 affiliates BioTrack Capital Management Ltd; PitchBook/Form D BioTrack Capital Fund I/II; Tracxn BioTrack Capital |
| `aegis-group-partners` | `agp`, `agp-3` | IAPD 310477/310478 (NYC) funds IP Successor Fund 21 / Celestial Successor Fund; PitchBook: IP Successor Fund 21 managed by Aegis Group Partners, New York |
| `north-coast-ventures` | `ncaf` | IAPD 311015 ADV website northcoast.vc, funds North Coast Angel Fund II-IV, affiliate North Coast Ventures Management |
| `sbva` | `sv-investment` | IAPD 312011 affiliates SBVA Corp / SBVA Capital Holdings; SEC 13G/Form D China Ventures Fund (GP SV GP I, ultimate parent SoftBank Ventures Asia = SBVA) |
| `eminence-ventures` | `eminence-marvelous-gp` | IAPD 313468 ADV website emventures.cn, LinkedIn "Eminence Ventures 靖亚资本", fund Eminence China Enterprise Fund II |
| `yu-galaxy` | `yu-star` | IAPD 318251 (Palo Alto) fund Yu Star Fund I; PitchBook: Yu Star Fund I managed by Yu Galaxy (yugalaxy.com); Form D related person Pingrong Yu |
| `mountain-group-partners` | `mgc-venture-partners`, `mgp-venture` | IAPD 318455/298455 ADV website mtngp.com, LinkedIn mountain-group-partners |
| `viola-ventures` | `viola-opportunity-management-fund-1-limited-partnership` | IAPD 319245 ADV website viola-group.com, related advisers are Viola Ventures entities; Radient/AUM13F Viola Opportunity I |
| `runtide-capital` | `runtide-capital-spv` | IAPD 320744 ADV website runtidecapital.com; same firm as IAPD 307164 Runtide Capital |
| `nashville-capital-network` | `ncn-management-company`, `ncn-management-company-pf` | IAPD 321890/289601 ADV website nashvillecapital.com "Nashville Capital Network" |
| `trium-group` | `trium-ventures-gp` | IAPD 322206 (909 Montgomery St SF); PitchBook: Trium Venture Partners I managed by The Trium Group (triumgroup.com, same address); Form D related persons Darren Gold, Andrew Blum |
| `highlight-capital` | `hlc-vgc-management-iv` | IAPD 323435 ADV website hlcfund.com; hlcfund.com "HighLight Capital" (弘晖资本); LinkedIn highlight-capital |
| `grove-ventures` | `grove`, `mata-technologies-ventures-iii-2021` | IAPD 324050 ADV website grovevc.com, funds Grove Ventures; grovevc.com "Grove Ventures" |
| `sabi-fund` | `sabi` | IAPD 326511 fund SABI Fund I; SEC Form D "SABI Fund I - SABI Fund LP"; Startup Intros profile "Sabi Fund" |
| `greenfield-partners` | `greenfield-cities-2`, `greenfield-cities` | IAPD 328032/309322 ADV website greenfield-growth.com, funds Greenfield Partners, affiliate Greenfield Cities LLC |
| `razor-capital` | `razor-gp-2`, `razor-aptos` | IAPD 332108/332107 (Dubai, managing member Abhinav Munshi); razorcapital.net About Us: Abhinav Munshi co-founder of Razor Capital |
| `msa-capital` | `magic-stone-alternative-private-equity`, `msa-china` | IAPD 332202/335450 ADV website msacap.com "MSA Capital" |
| `igah-ventures` | `igah-gestora-ltda`, `pevc-i-general-partner` | IAPD 332786/317507 fund Igah Ventures IV, affiliate IGAH Gestora; SEC Form D Igah Ventures IV LP; Startup Intros "Igah Ventures" |
| `second-century-ventures` | `second-century-ventures-gp` | IAPD 333148 (430 N Michigan Ave Chicago); nar.realtor and scv.vc "Second Century Ventures" (NAR) |
| `flywheel-fund` | `flywheel` | IAPD 338946 (Bloomington IN) fund Flywheel Fund VI; SEC Form D related person Eric Steele; flywheelfund.vc "Flywheel Fund"; Inside Indiana Business |
| `startup-capital-ventures` | `startup-capital-ventures-management-co` | IAPD 341911 ADV websites startupcv.com / scv-sbi.com; startupcv.com "Startup Capital Ventures" |
| `capstar-ventures` | `wxyz` | IAPD 342237 ADV websites capstar.vc / capstarventures.com, affiliates Capstar Ventures GP |
| `alder` | `alder-iii-d` | Finansinspektionen EuVECA register (Alder III (D) AB); alder.se "Alder completes closing of Alder III" |
| `atlantic-bridge` | `atlantic-bridge-innovation`, `atlantic-bridge-early-stage` | Irish CRO 774502 / CBI EuVECA register: Atlantic Bridge Innovation III GP Ltd at 22 Fitzwilliam Sq (Atlantic Bridge); EuVECA register Atlantic Bridge Early Stage GP Ltd |
| `ballista-capital` | `ballista-capital-spv`, `ballista-capital-spv-3` | Bolagsverket via allabolag/Syna (Ballista Capital SPV AB, Stockholm) + ballistacapital.se "Om Ballista" |
| `consolid-equity` | `consolid-equity-iii-d`, `consolid-equity-iii-e` | Bolagsverket via merinfo (Consolid Equity III (E) AB) + consolid.se + PEI profile "Consolid Equity"; Vinge press release |
| `forbion` | `fcpm-iii-services` | Dutch KvK 56419899 via GLEIF/Bloomberg LEI + CNMV register: FCPM III Services B.V. (Naarden) manages Forbion funds |
| `gen-ii-fund-services` | `gen-ii-management-company-luxembourg` | FSMA register + gen2fund.com group entities: Gen II Management Company (Luxembourg) is Gen II Fund Services (fund administrator / AIFM) |
| `northcap-partners` | `ncp-ivs-iii-gp-aps` | Danish CVR 33373104 (directors Kim Wiencken, Thomas Weilby Knudsen) + northcap.vc team page + PEI profile "NorthCap Partners" |
| `nea-partners` | `never-eat-alone-general-partners` | Bolagsverket via Bolagsradar (Never Eat Alone General Partners III AB) + FI EuVECA register + neapartners.se "NEA Partners" |
| `odewald-kmu` | `odewald-kmu-iii-gesellschaft-fur-beteiligungen-mbh` | Handelsregister Berlin via OpenRegister + EuVECA register + odewaldkmu.com "Odewald KMU" |
| `oltre-impact` | `oltre-impact-societa-di-gestione-del-risparmio-spa-gestore-euveca`, `oltre-ii-sicaf-euveca-spa` | oltreimpact.com: Oltre II SICAF EuVECA is managed by Oltre Impact SGR (formerly Oltre Venture); EIF/Fondo Italiano press release |
| `procuritas` | `procuritas-capital-investors-vii-d` | FI EuVECA register (Procuritas Capital Investors VII (D) AB) + procuritas.com "PCI VII" |
| `stoaf` | `stoaf-iii-venture-partners` | Bolagsverket via allabolag/Syna (STOAF III Venture Partners AB, Stockholm) + stoaf.se |
| `3ts-capital-partners` | `tcee` | Luxembourg RCS B240552 via North Data: TCEE Fund IV GP Sàrl shareholder/adviser 3TS Capital Partners; 3tscapital.com SFDR disclosure |
| `v-bio-ventures` | `v-bio-management-2` | Belgian KBO 0758.543.760 (V-Bio Management 2, Gent) manages V-Bio Fund 2; v-bio.ventures press release |
| `yield-lab-europe` | `yield-lab-europe-fund-1` | gov.ie / Enterprise Ireland press release + theyieldlab.eu SFDR (Yield Lab Europe Fund 1) |
