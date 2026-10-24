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
