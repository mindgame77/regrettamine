# Rules audit

Read-only inventory, 2026-10-27. No rows were changed. Live counts are the 10 lab firms (a16z, Y Combinator, Sequoia, Lightspeed, General Catalyst, Plug and Play, Accel, Greenoaks, Khosla Ventures, MIO Partners) unless a count says otherwise.

There is no file named “system map.” The closest current map is `docs/HOW_IT_WORKS.md` §11. `docs/design/DATA-ARCHITECTURE.md` is an unapplied draft and is marked old below.

Status counts: **34 active**, **20 old**, **8 doc-only**, **12 code-only**, **8 conflicts**. A conflict is also listed under the status of each side, so the five counts overlap on those eight.

## How a rule was marked

- **Active.** The database, the edge function, or the page enforces it, and the live path still uses it.
- **Old.** It names something that is gone or that the live page no longer reads: `src/`, the old website, dropped functions, `vc_scores` as the page score, `legal_matters` as the legal section, GitHub Pages as the host, or a full build on every push.
- **Doc-only.** Written down, and not enforced.
- **Code-only.** Enforced, and not written as a rule.
- **Conflict.** Two current rules disagree.

Suggestion is keep, remove, update, write down, or enforce.

## Rule inventory

| Id | Rule in plain words | Where it lives | Status | Suggestion |
|---|---|---|---|---|
| A1 | Only `toxy-enricher` writes a public page, and it does that when the enrich call is stored. Researcher dumps stay in the holding area. | `docs/HOW_IT_WORKS.md` §2–3; `research_enrich`; triggers in `supabase/migrations/20261027050000_enricher_only_publish.sql` | Active | Keep |
| A2 | One bot can store at most 20 research dumps a minute. | `docs/DATA_RULES.md` §1; `research_submit` | Active | Keep |
| A3 | Each fact is one object with the fields for its section, plus a source link. | `docs/DATA_RULES.md` §1; `docs/GOLD_EXAMPLES.md`; `_check_item` | Active | Keep |
| A4 | Free text is a note and is never published. `{"item": "..."}` is refused. Top-level notes are saved only for the 10 lab firms. | `docs/DATA_RULES.md` §1; `checked_items` in `20261028010000_payload_notes.sql` | Active | Keep |
| A5 | A source must be an http(s) URL. `.gov` and `.mil` are refused except sec.gov and the courts. Search and chat pages are refused. | `docs/SOURCE_TIERS.md`; `docs/ENRICHER.md`; `_src_reason`; `research-ingest` `validate` | Active | Keep |
| A6 | A person name is one person: no lists, digits, brackets, or “and,” and no more than six words. | `docs/DATA_RULES.md` §2; `_person_name_bad` | Active | Keep |
| A7 | An AUM value must contain a number. | `docs/DATA_RULES.md` §2; `_check_item` / `checked_items` | Active | Keep |
| A8 | Single dates are `YYYY`, `YYYY-MM`, or `YYYY-MM-DD`. A timeline range may stay as written. | `docs/DATA_RULES.md` §1; `_data_rule` | Active | Keep |
| A9 | Inside one table, a duplicate adds its source: person plus kind, fund name, LP name, legal key, timeline date plus event, press exact URL. | `docs/DATA_RULES.md` §2; `_promote_one` | Active | Update: say the match does not cross tables |
| A10 | A different value for the same fact is a conflict. The page keeps the old value. | `docs/DATA_RULES.md` §2; `_promote_one` | Active | Keep, and see K1 |
| A11 | Leads, allegations, and fixes are held. On the 10 lab firms a lead with no source is rejected, and an allegation without a court or regulator link is rejected. A lab conflict is copied to `conflict_weekly`. | `docs/DATA_RULES.md` §2; `docs/HOW_IT_WORKS.md` §4; `_promote_one`; `20261028040000_lab_rules.sql` | Active | Keep, and see K2 |
| A12 | News draws a press or timeline row only when `check_mark` is `checked_correct`. A new row stays `not_checked`. | `docs/DATA_RULES.md` §4; `docs/CONFLICT_RULE.md` press section; `_sec_items` | Active | Keep |
| A13 | On the News draw only: one card per normalized link, one card per story within 7 days, and nothing dated before 2023. | `docs/DATA_RULES.md` §4; `launch/js/company.js` `buildNews` | Active | Keep |
| A14 | On the Overview draw only: hide Other names, Type, Staff, Private funds, Legal entity, Sanctions screening, and empty or “Not found”; strip CRD and SEC file numbers; fold founders into Founded. | `docs/DATA_RULES.md` §4a; `launch/js/company.js` `overviewRows` | Active | Update: the label `Overview` is not in the hide list |
| A15 | Locked, removed, and hidden rows are not rewritten or brought back by a publish. | `docs/HOW_IT_WORKS.md` §5; `_promote_one` | Active | Keep |
| A16 | A people row that is a Schedule A note, a URL, or longer than 300 characters is hidden on insert. | `supabase/migrations/20261026040000_people_note_guard.sql`; `launch/js/company.js` `isNoteText` | Active | Update: sentences under 300 characters still show |
| A17 | Overview, funds, LPs, legal, people, and timeline are not returned without a source. Press and the 10 check pills are the exceptions. | `_sec_items` | Active | Write down |
| A18 | A firm page is returned only when the firm is published, not deleted, not a test, and `data_status` is real. | `firm_page` | Active | Keep |
| A19 | Search suggestions come from the display name, short name, slug, and aliases of those public firms, at most 8. | `firm_suggest` in `20261024220000_firm_aliases.sql`; `launch/js/search.js` | Active | Write down the limit |
| A20 | A dump’s LP list needs a name, status `confirmed` or `lead`, and a real URL. At most 100 names are stored, unique on firm plus name plus fund. | `research-ingest` `validateLps`; `research_store_lps` | Active | Keep |
| A21 | Every source URL is tagged trusted, other, or not a source. A fact with no usable source is hidden until a source is added. | `docs/SOURCE_TIERS.md`; `source_tier` | Active | Keep, and see P18 |
| A22 | A quote or press item on the firm’s own site or owned channel is labelled own media. | `docs/ENRICHER.md`; `_own_media` inside `_sec_items` | Active | Keep |
| A23 | A same-name sanctions hit is not a finding. The check stays Clear and a muted line names the list. | `docs/ENRICHER.md`; `launch/js/company.js` `nameOnlyNotes` | Active | Keep |
| A24 | Founder reviews on the page are `review_type = founder`, public, and approved. | `_firm_activity` | Active | Write down who sets approved |
| A25 | Deals on the strip are `investments` with `data_status = real`. The “last 12 months” count is 365 days. | `20261026030000_firm_page_activity.sql`; `launch/js/company.js` `activity` | Active | Keep |
| A26 | On the 10 lab firms, the fund tile uses a raised amount, then an earlier fund line, then assets. | `launch/js/company.js` `activity` | Active | Write down |
| A27 | Four jobs run: on-demand tick every 2 minutes, yearly refill hourly, lapsed-plan downgrade hourly, search-log purge nightly. | `docs/HOW_IT_WORKS.md` §9; live `cron.job` | Active | Keep |
| A28 | CI builds the 10 lab firms. A full build runs only when the workflow is started by hand with rollout true. Docs-only pushes do not build. | `docs/HOW_IT_WORKS.md` §8; `.github/workflows/pages.yml` | Active | Keep |
| A29 | A visitor request does not create a page. It files a queue row for Researcher 3. Rate limits apply. | `docs/FIRM_REQUESTS.md` | Active | Keep |
| A30 | Two pages for one firm are merged by hand. The dropped page is soft-deleted and its names stay searchable. | `docs/DEDUPE.md`; `merge_firms` | Active | Keep |
| A31 | `app_settings.lock_enabled` is false, so firm pages open without spending a credit. | `20261027174716_lock_enabled.sql`; live value `false` | Active | Update `docs/ON_DEMAND.md`, which still describes the lock |
| A32 | A new press or timeline publish does not set `checked_correct`. | column default; `_promote_one` insert | Active | Write down next to A12 |
| A33 | An alias is unique per firm and lowercased text. Allowed sources are `sec_legal`, `previous_display`, `queue_name`, and `merged`. | `firm_aliases` check constraint; `docs/DEDUPE.md` | Active | Keep |
| A34 | On the 10 lab firms, a new timeline sentence that matches one of two patterns is also stored as an investment. | `20261028020000_lab_deals.sql`; `docs/HOW_IT_WORKS.md` §4 | Active | Write the two sentence patterns into the doc |
| O1 | Add a firm by editing JSON, then fill `legal_matters`, `people`, and `fund_people` in the table editor as the page. | `README.md` “Add a fund in JSON” and “Add or edit a firm” | Old | Update the README to the launch tables |
| O2 | Setup is the first four SQL files, then seed. | `README.md` Supabase setup | Old | Update: migrations run in name order |
| O3 | The legal section the visitor sees is `legal_matters`, filings, and docket lines. | `docs/data-model.md` | Old | Update: the page reads `firm_legal_items` |
| O4 | The page shows a Toxy Score, and anonymous visitors get 2 reports then 5 more. | `docs/data-model.md` Scores and Gating | Old | Update: no score is drawn; the lock is off |
| O5 | The homepage row is `list_score`, and `report_slug` means “coming soon.” | `docs/data-model.md` | Old | Remove from the live-page description |
| O6 | The firm root is `vc_profiles`, scores live in `vc_scores`, and a daily job hard-deletes firms after 30 days. The draft says none of this is applied. | `docs/design/DATA-ARCHITECTURE.md` | Old | Remove or mark “not the live model” |
| O7 | The score block on the page is `vc_scores`. | `docs/design/VC-PROFILE.md` | Old | Remove |
| O8 | Live CSS and copy live in `src/css` and `src/js/strings.js`. | `docs/design/README.md`; `.cursor/rules/design.mdc` | Old | Update to `launch/` |
| O9 | The old website functions were only revoked and still exist. | `docs/CHANGELOG.md` 2026-10-27 1:40 PM line | Old | Update: they were dropped in #192 |
| O10 | Applying the press mark shows zero press. | `docs/CHANGELOG.md` 2026-10-27 9:00 AM line | Old | Leave as history; the later news migration set marks |
| O11 | Press shows when `data_status` is real, the link is not hidden, and the URL is set. | `docs/CONFLICT_RULE.md` “Press check mark” | Old | Update: readers use `check_mark` |
| O12 | GitHub Pages hosts the site. | `launch/HOW-TO-CHANGE.md`; `launch/legal/privacy.md` | Old | Update: Cloudflare serves regretamin.com |
| O13 | The public score page is `src/scoring.html`. | `score/README.md` (it already says the page was removed) | Old | Keep the archive; do not treat it as live |
| O14 | Accel is a gold example. | older bot notes; `docs/GOLD_EXAMPLES.md` already says it is not | Old | Keep the “no longer gold” line |
| O15 | Every push to main builds every firm. | older workflow | Old | Already replaced by A28 |
| O16 | Hero cards under the firm name show staff, AUM, and founded. | removed in #181; `docs/CHANGELOG.md` | Old | Keep the changelog line only |
| O17 | `research-ingest` logs in as `bot_ingest` using `BOT_INGEST_DB_URL`. | `docs/ROLLBACK_3B.md`; changelog #165–#167 | Old | Keep the rollback note only |
| O18 | A researcher upload copies checks and facts onto the page. | old triggers; now `promote_bot_facts_trg` and `checks_from_upload_trg` return null | Old | Remove leftover comments that still say the copy happens |
| O19 | `auto_promote_enrichment` decides whether the enricher publishes. | `docs/HOW_IT_WORKS.md` still mentions the switch; `docs/ENRICHER.md` says it no longer gates | Old | Delete the switch from the guide |
| O20 | `ui_strings` overrides page copy at runtime. | `docs/design/README.md`; design rule | Old | The launch page reads `launch/copy.json` |
| D1 | When two sourced values disagree, the official source wins, then the newer dated source. | `docs/CONFLICT_RULE.md` | Doc-only | Enforce, or change the doc to match the checker |
| D2 | The page shows the official value while the case waits on a weekly list. | `docs/CONFLICT_RULE.md` | Doc-only | The lab weekly copy exists; the “show the official value” part does not |
| D3 | Bots compare their output to the Y Combinator and a16z pages before sending. | `docs/GOLD_EXAMPLES.md` | Doc-only | Keep as a bot instruction; there is no code check |
| D4 | Nothing is deleted without Alex’s approval. | `docs/DATA_RULES.md` §3; `docs/HOW_IT_WORKS.md` §5 | Doc-only | Keep as a process rule |
| D5 | The 0–100 score formula (rates, not counts, under 1% costs nothing). | `docs/toxy-score-v2-rules.md`; `score/` | Doc-only | The live page does not run it. Keep the archive |
| D6 | The 10 pills are derived from `vc_source_facts` by `launch/checks.py`. | `launch/checks.py` | Doc-only | The page reads `firm_check_rows` |
| D7 | The sanctions pill means OFAC SDN, the UK list, the EU map, and the UN list were searched. | `docs/SOURCE_TIERS.md` names those hosts as trusted | Doc-only | The pill copy only says “government sanctions lists” |
| D8 | List builders follow a written search method (“Strategy C,” which registries, which years). | queue values such as `list-builder batch_OT-RESORT-2 (Strategy C)` | Doc-only | No written rule. Write one |
| C1 | The two sentence patterns that become a lab deal. | `_deal_from_text` | Code-only | Write down |
| C2 | Sequoia’s assets display is `$82.2B`, and two named funds were filled by hand. | `20261028030000_lab_funds_aum.sql` | Code-only | Write down as a one-firm exception |
| C3 | Assets text is the first dollar figure on an Item 5F or “regulatory AUM” fact, else `aum_display` if it starts with `$`. A trailing B, M, or K is dropped. | `_firm_assets` | Code-only | Write down |
| C4 | The earlier-fund fallback parses “Name · $amount · date” and skips AUM sentences. | `launch/js/company.js` `earlierFund` | Code-only | Write down |
| C5 | A stored pill state `red` is drawn as Review. | `launch/js/company.js` `tpill` | Code-only | Write down |
| C6 | A portfolio company is matched on the lowercased name only. | `_lab_save_deal` | Code-only | Write down |
| C7 | A check row with no itemized findings links a CourtListener search of the legal name. | `launch/js/company.js` `courtSearch` | Code-only | Write down |
| C8 | `firm_details` keeps `real` and `needs_proof` facts, drops name-only wording, and keeps one row per check plus detail. | `firm_details` | Code-only | Write down |
| C9 | LP rows with the same label become one card, and the count is the number of names. | `launch/js/company.js` `groupLps` | Code-only | Write down |
| C10 | The activity collector and the Y Combinator batch loader that filled `investments`. | `investments.source_system = activity_collector_2026_10_25` | Code-only | Write down, or stop using it |
| C11 | Section-count alerts fire when a section drops, or jumps by more than 20 or by more than 1.5×. | `docs/HOW_IT_WORKS.md` §9; `section_count_alerts` | Active (written) | Kept out of the code-only list on purpose |
| C12 | Search-log rows with a firm are deleted after 30 days. Rows with no firm stay. | `docs/HOW_IT_WORKS.md` §9; `bots.purge_old_search_log` | Active (written) | Same |
| K1 | Official source wins, versus the checker keeps whatever is already on the page. | `docs/CONFLICT_RULE.md` vs `_promote_one` | Conflict | Enforce the written ranking, or change the doc |
| K2 | Leads are never public, versus stored LP values and legal titles that say “Lead” are still drawn. | `docs/DATA_RULES.md` §2 vs `_sec_items` (no lead filter) | Conflict | Hide the stored lead rows, or stop calling them leads |
| K3 | Press shows from `hidden` and `data_status`, versus press shows from `check_mark`. | `docs/CONFLICT_RULE.md` vs `_sec_items` | Conflict | Update the doc |
| K4 | The README and data model name `legal_matters`, `people`, `funds`, and `score_results` as the page, versus the page reads `firm_legal_items`, `firm_people_roles`, `firm_profile_facts`, and no score. | `README.md`, `docs/data-model.md` vs `firm_page` / `company.js` | Conflict | Update the old docs |
| K5 | Spending a credit unlocks a locked page, versus the lock is off and pages open for everyone. | `docs/ON_DEMAND.md` vs `lock_enabled = false` | Conflict | Update the on-demand doc to the switch |
| K6 | “Scores follow the v2 rules” and “the score copy is not what the live site runs.” | `docs/HOW_IT_WORKS.md` §4, both sentences | Conflict | Say the formula is an archive and the page has no score |
| K7 | One checker covers every data kind, versus deals, the 10 pills, `vc_source_facts`, `sanctions_checks`, and scores are not on that path. | `docs/DATA_RULES.md` opening vs `_promote_one` | Conflict | List the kinds the checker does not publish |
| K8 | Publish keeps press and timeline as two rows, versus the page treats the same link as one card and does not delete the second row. | `docs/DATA_RULES.md` §2 and §4 | Conflict | Say the display merge is not a dedupe |

The search-log purge is already A27. The section-count alert is the same family of written rules and is not an extra active id. The code-only list is C1 through C10, plus these two:

| Id | Rule | Where | Status | Suggestion |
|---|---|---|---|---|
| C11b | `firm_suggest` returns at most 8 hits and ranks a prefix match first. | `firm_suggest` | Code-only | Write down |
| C12b | Account “My firms” shows `firms.name`, not `display_name`, plus pill counts from `firm_check_rows`. | `my_firms` | Code-only | Write down |

Header counts use that set: active 34 (A1–A34), old 20 (O1–O20), doc-only 8 (D1–D8), code-only 12 (C1–C10, C11b, C12b), conflicts 8 (K1–K8).

## Problem list

Every data kind is here. “No problem found” means the check named in that row came back clean. Counts are lab firms unless noted. Measured 2026-10-27 from the live database, read only.

### 1. Firm display name

No problem found. On all 10 lab firms, `firms.name` and `firms.display_name` are the same string. The header reads `coalesce(display_name, name)` (`firm_page`). Checked those two columns.

### 2. Legal name

| | |
|---|---|
| Data kind | Firm legal name |
| Problem | Sequoia’s `legal_name` is empty (1 of 10). Plug and Play’s legal name is `PLUG AND PLAY FUND MANAGEMENT I, LLC`, a fund entity, not the brand on the page. The other eight have a legal name. |
| Rule | `firm_page` sends `sec_name` as `coalesce(legal_name, name)`. No written rule for when the legal name must be the adviser rather than a fund GP. `docs/DEDUPE.md` says fund-named pages were merged. Status: code-only for the fallback; doc-only for “one firm, one legal name.” |
| Proposed solution | Fill Sequoia’s legal name from the SEC adviser record. Replace Plug and Play’s legal name with the adviser, and keep the fund name as an alias. |
| Risk | A court-search link uses `sec_name` (`company.js` `courtSearch`). An empty or fund-level name searches the wrong party. |

### 3. Aliases

No problem found for cross-firm clashes. 0 lab aliases sit on two firms. Unique on firm plus lowercased text (`firm_aliases`). Each lab firm has 1 to 3 aliases. Search uses them (`firm_suggest`).

### 4. Slug

No problem found. The 10 lab slugs are unique. `firm_page` looks up `firms.slug`. Old slugs redirect through `firm_redirect` (`docs/DEDUPE.md`).

### 5. Logo

No problem found. The header logo is the Regretamin lockup, not a firm logo. `launch/js/company.js` does not read a logo column. Checked the Sequoia page shell and the script.

### 6. Sanctions

| | |
|---|---|
| Data kind | Sanctions (OFAC and the other lists) |
| Problem | All 10 lab Sanctions pills are Clear. Five firms have no row in `sanctions_checks`: Accel, Greenoaks, Khosla Ventures, MIO Partners, and Y Combinator. Accel is the example: pill Clear, 0 screening rows. The page line says “Searched government sanctions lists” and does not name OFAC SDN, the UK list, the EU map, or the UN list. |
| Rule | Pill text is `firm_check_rows` n=1. The muted line is `launch/copy.json` `searched.1`. Trusted hosts are named in `docs/SOURCE_TIERS.md`. Nothing ties the pill to those hosts. Status: conflict (K7) and doc-only (D7). |
| Proposed solution | A Clear pill requires a screening row that names the lists. Until then the pill stays “Not checked yet.” |
| Risk | A Clear pill with no row reads as “we checked OFAC” when that check is not stored. |

### 7. Legal

| | |
|---|---|
| Data kind | Legal |
| Problem | Three lab case keys are stored twice, and the “Lead” copy is still shown. Accel has both “Severt v. UiPath” and “Lead (allegation, not verified): LEAD: Severt v. UiPath,” both not hidden. Khosla has the same pair for Hood v. Cannon and for Adamo v. Nextdoor. |
| Rule | `_legal_key` ignores a Lead prefix (`20261026180000_stable_keys_checked_counts.sql`). `docs/DATA_RULES.md` says leads are never public. `_sec_items` does not filter them. Status: conflict (K2). |
| Proposed solution | Hide the Lead copy when the same case key already has a public row. Stop new leads at publish (that part already works). |
| Risk | Hiding the Lead row removes a source that the public row might not have. Add that source to the public row first. |

### 8. Regulatory

| | |
|---|---|
| Data kind | Regulatory |
| Problem | Regulator news lives in three places that do not match. MIO’s check 4 says Review, “2 actions.” `regulatory_records` for MIO is 0. `firm_legal_items` with group `regulator` is 2. Lightspeed’s registration pill (check 8) is still “Not checked yet” while the firm has a regulatory record. |
| Rule | The legal section reads `firm_legal_items` (`_sec_items`). The pill reads `firm_check_rows`. `regulatory_records` is in `docs/data-model.md` and is not what the section reads. Status: old for the data-model table (O3); conflict (K4, K7). |
| Proposed solution | Pick `firm_legal_items` as the only regulatory store the page uses, and set the pill from those rows. |
| Risk | A pill that is edited by hand will drift again the next time someone loads a record into the other table. |

### 9. People

| | |
|---|---|
| Data kind | People |
| Problem | Accel has 6 hidden people rows that are Schedule A sentences, not names (for example “London Schedule A…”). The guard caught those. Greenoaks has 1 visible row the guard missed: “Board seat: Neil Mehta - Coupang, Inc. director since Dec 2010…”. It is under 300 characters and has no URL, so it is drawn as a person. Stable-key collisions on lab people: 0. |
| Rule | `_people_note` and `isNoteText`. Status: active, and too narrow (A16). |
| Proposed solution | Hide a people name that contains a date, “board seat,” or “Schedule A,” even when it is short. |
| Risk | A real name with a suffix such as “Jr” is safe. A role that was stored in the name field would disappear until it is split into name and role. |

### 10. Funds

| | |
|---|---|
| Data kind | Funds |
| Problem | Fund facts and the `funds` table are not the same list. Lightspeed has 64 `funds` rows and 4 profile-fact lines. Accel has 19 profile-fact lines and 0 `funds` rows, so the activity tile cannot use a fund. Seven lab fund keys are shared by more than one row. a16z has two visible lines that both say `$1.7B`. Khosla’s lines that start “Venture capital” share one key even when the amounts differ. |
| Rule | Enricher funds go to `firm_profile_facts` (`_promote_one`). The tile reads `funds` (`_firm_activity`). `_fund_key` uses the words before the first separator. Status: active inside each table (A9); conflict across tables (K7). |
| Proposed solution | One fund row, with the filing amount on it, and a key that includes the fund name rather than the first two words. |
| Risk | Merging the coarse Khosla key would collapse different funds. Split those keys before any merge. |

### 11. AUM

| | |
|---|---|
| Data kind | AUM |
| Problem | `_firm_assets` is null for 4 lab firms: Accel, Khosla Ventures, Y Combinator, and Plug and Play (Plug and Play’s `aum_display` is `0.13`, which the helper skips because it does not start with `$`). Greenoaks returns `$18.27`. Sequoia is the clean case: the hero value is `$82.2B` and the tile can keep the B. The helper’s regex does not keep a trailing B, M, or K, so a firm that relies on the helper alone can lose the unit. |
| Rule | `_firm_assets` in `20261025200000_display_header_and_dates.sql`. The tile is `aumTile` in `company.js`. Sequoia’s `$82.2B` was set by `20261028030000_lab_funds_aum.sql`. Status: code-only (C2, C3). |
| Proposed solution | Store one display string with its unit, from Item 5F, and use that string on the tile. |
| Risk | Showing `$18.27` as assets under management is worse than showing nothing. Hide a figure that is under $1 billion until a person checks it. |

### 12. Deals

| | |
|---|---|
| Data kind | Deals |
| Problem | Six lab firms have 0 investments: Accel, General Catalyst, Greenoaks, Khosla, Lightspeed, and MIO. Y Combinator has 811, loaded by `activity_collector_2026_10_25`. One example is Keres: the round is the sentence “YC batch investment, F26, batch began Oct 2026…”, amount empty, source `ycombinator.com/companies/keres`. Sequoia has 10, all inside the 12-month window, copied from timeline lines. An enricher deal object is not what `_promote_one` writes. |
| Rule | Gold shape in `docs/GOLD_EXAMPLES.md`. Writer for new lab lines is `_deal_from_text` (two patterns). Page filter is `data_status = real`. Status: the gold shape is doc-only for this table; the regex is code-only (C1, C10). |
| Proposed solution | Publish the gold deal object into `investments`, and reject a round that is longer than a round name. |
| Risk | The 811 Y Combinator rows are what the page lists today. Tightening the rule hides them until they are rewritten. |

### 13. Portfolio companies

| | |
|---|---|
| Data kind | Portfolio companies |
| Problem | No duplicate company names inside one lab firm (0). The gap is identity and coverage. A company is matched on the lowercased name only. Six lab firms have 0 companies because they have 0 investments. Accel is the example: 0 companies. Y Combinator’s sources are the firm’s own company pages. |
| Rule | `_lab_save_deal` inserts `portfolio_companies` on lowercased name. No written rule for a domain or a second identifier. Status: code-only (C6). |
| Proposed solution | Match on domain when the source URL has one, and do not treat a missing investment list as an empty portfolio on the page. |
| Risk | Two different companies with the same name would merge. A domain check prevents that; a name-only check does not. |

### 14. News

| | |
|---|---|
| Data kind | News (press and timeline) |
| Problem | The same link is stored twice because publish never compares the tables. Today 9 lab stories share a normalized link on both the press URL and `timeline_events.source_url`, and 4 more share a link only through the timeline’s source citation. Example, a16z, `a16z.com/why-did-we-raise-15b`: press “Why did we raise $15B (a16z's own post)” and timeline “Raised over $15B across new funds,” both `checked_correct`, 2026-01-09. The browser can draw one card. The second row stays. A new publish stays `not_checked`, so it does not show until a person sets the mark. |
| Rule | A9 and A12 and A13. Status: conflict (K8). |
| Proposed solution | On publish, if the normalized link is already on the other table, add the source to the existing card’s sources and do not insert a second showable row. |
| Risk | A timeline tag (Court, Fund, People) must be kept on the surviving card. The display rule already does that. A publish rule has to do it too. |

### 15. Overview facts

| | |
|---|---|
| Data kind | Overview |
| Problem | Eight lab firms each have 3 profile rows whose label is `Overview`, 24 rows. They are long paragraphs. Accel’s values include “Accel is a venture firm…” and “US: Accel Management Co. L.L.C (CRD 331435…”. The draw rules do not hide the label `Overview`. a16z and Y Combinator have 0 such rows. Unsourced non-hidden profile facts on the lab firms: 0. |
| Rule | `docs/GOLD_EXAMPLES.md` says one label is one short fact. `overviewRows` hides a fixed label list and does not include `Overview`. Status: active hide list (A14), incomplete. |
| Proposed solution | Hide the label `Overview`, and reject a new overview value that is longer than one sentence. |
| Risk | Those paragraphs hold the only copy of a CRD or an address on some firms. Move the one fact out before hiding the paragraph. |

### 16. Check-detail facts

| | |
|---|---|
| Data kind | Check-detail facts (`vc_source_facts`) |
| Problem | Five lab firms have 0 of these rows: Accel, Greenoaks, Khosla, MIO, and Y Combinator. Their pills are still mostly Clear. a16z has 87, Sequoia 138, General Catalyst 106, Lightspeed 112, Plug and Play 58. The enricher does not write this table, and researcher uploads no longer copy into it. |
| Rule | `firm_details` reads the table. `checks_from_upload_trg` returns null. Status: conflict (K7); the reader is code-only (C8). |
| Proposed solution | Either the enricher writes these rows, or a Clear pill is not allowed when the detail table is empty. |
| Risk | Turning Clear into “Not checked yet” on five firms changes the page visitors see today. |

### 17. Sources present

No problem found for missing links on lab profile facts. Non-hidden `firm_profile_facts` with no `fact_sources` row: 0 on all 10 firms. `_sec_items` already drops a row with an empty source list (A17).

### 18. Source tier on the pill

| | |
|---|---|
| Data kind | Sources |
| Problem | The visitor cannot see whether a pill is a trusted registry or any other page. `source_tier` tags the URL. The page prints the host name and the date. Sequoia’s press pills are the example: 5 press rows are returned, and none of the pill text says trusted or other. |
| Rule | `docs/SOURCE_TIERS.md` is active for the tag (A21). Nothing in `company.js` reads the tag. Status: code-only gap. |
| Proposed solution | Print “Registry” or “Other source” on the pill from `source_tier`. |
| Risk | A trusted host that is wrong about this firm would look stronger. The tag is about the host, not about whether the sentence is true. |

### 19. Reviews

| | |
|---|---|
| Data kind | Reviews |
| Problem | Khosla has 4 stored reviews and 0 that the page will show. Lightspeed and MIO have 0 stored. Sequoia’s page payload counts 8 public founder reviews. a16z has 21 stored and the earlier count of public approved founder rows was 11. No written rule says who sets `moderation_status` for a bot quote. |
| Rule | `_firm_activity` requires public, approved, and `review_type = founder` (A24). Status: active filter; the approval step is doc-only. |
| Proposed solution | Write who may approve a bot quote. Do not leave rows stored and invisible with no owner. |
| Risk | Approving them in bulk would publish quotes nobody has read. |

### 20. The 10 checks

| | |
|---|---|
| Data kind | The 10 checks |
| Problem | The pills are a stored column, not a live count of the evidence. Khosla has 4 of 10 still “Not checked yet” and 0 `vc_source_facts`. Y Combinator has 5 still “Not checked yet.” Lightspeed’s registration pill is “Not checked yet.” New firms are inserted as `nc` and nothing in the enricher path updates them. |
| Rule | `firm_check_rows` is what `firm_page` returns. `launch/checks.py` is not what the page runs (D6). Status: conflict (K7). |
| Proposed solution | Recompute the pill when the evidence changes, and leave it `nc` when the evidence table is empty. |
| Risk | Hand-set pills such as a16z’s “1 open probe” would change if the recompute disagrees with the hand value. Compare first. |

### 21. Scores

| | |
|---|---|
| Data kind | Scores |
| Problem | The page has no score bar. Five lab firms still have one current `score_results` row: a16z, General Catalyst, Lightspeed, Plug and Play, and Sequoia. The other five have none. a16z is the example: a stored score, and the header does not draw it. |
| Rule | `docs/toxy-score-v2-rules.md` and `score/`. `docs/HOW_IT_WORKS.md` says that copy is not what the live site runs. `company.js` has no score block. Status: conflict (K6); the formula is doc-only (D5). |
| Proposed solution | Say in the product docs that the score is not on the page. Do not leave `vc_scores` and `score_results` described as the header. |
| Risk | None for the live page, because it already does not read them. Deleting the rows would be a separate decision. |

### 22. LPs

| | |
|---|---|
| Data kind | LPs |
| Problem | The same names sit in two homes, and nothing compares them. Lab profile rows: 45 (36 names). `bots.firm_lps`: 47 (41 names). Shared names: 33. Example, Accel, Adams Street Partners: the profile value is “Fund of funds · Accel Leaders Fund · Lead (not confirmed)” and the bot row is type `fund_of_funds`, status `lead`, fund “Accel Leaders Fund.” Sequoia’s page payload has no LP section. Several profile values still say “Lead,” and the page shows them as “Not confirmed.” |
| Rule | Profile dedupe is the name inside `firm_profile_facts` (`_promote_one`). Bot dedupe is name plus fund (`research_store_lps`). The page reads only the profile table and groups by label (`groupLps`). Status: conflict (K2, K7). |
| Proposed solution | Treat `bots.firm_lps` as the holding area and stop calling a duplicated name a second fact. Hide profile values that are still leads, or re-check them. |
| Risk | The page already shows one card per name. Hiding leads would shrink Accel’s LP list. |

### 23. Firm requests and list builders

| | |
|---|---|
| Data kind | Firm requests and list builders |
| Problem | `firm_requests` has 0 rows. The request path is written and unused. `research_queue` has 4,025 rows with a null `list_source`, so the origin is unknown. Named batches do exist: `list-builder batch_US-CA-3 2026-10-23 (Form D 2024Q1-2026Q3)` has 184 rows, and a batch named “Strategy C” has no written method. A queue row still does not create a page. That part was checked and holds. |
| Rule | `docs/FIRM_REQUESTS.md` covers visitor requests (A29). There is no written rule for list-builder sources (D8). Status: doc-only for the builders; active for “a queue row is not a page.” |
| Proposed solution | Require `list_source` on every new queue row, and write what Strategy C and the Form D window are. |
| Risk | Backfilling 4,025 nulls without a source would invent an origin. Leave the old rows null and require the field from now on. |

## Cross-cutting weak points

1. Two homes, and dedupe stays inside one table. Press is not checked against timeline. Profile LPs are not checked against `bots.firm_lps`. Fund facts are not checked against `funds`. Legal items are not checked against `vc_source_facts` or `regulatory_records`.
2. A publish is not a check. New press and timeline stay `not_checked` and do not show.
3. “Leads are never public” is true for a new item and false for rows already stored.
4. News merging, the 2023 cutoff, the overview rewrite, and LP grouping happen in the browser. The stored row stays.
5. The 10 pills, `vc_source_facts`, sanctions rows, and the score are not on the enricher path.
6. Stable keys are coarse. A legal key ignores “Lead.” A fund key uses the words before the first separator.
7. The conflict document says the official source wins. The checker keeps the page value.
8. There is no written rule for where list builders look, and no written rule that chooses press versus a timeline event.
9. A Sanctions pill can read Clear when `sanctions_checks` has no row (5 lab firms).
10. The assets helper drops the unit, and 4 lab firms have no assets figure at all.
