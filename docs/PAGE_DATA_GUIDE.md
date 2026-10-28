# Page data guide

This is the only rulebook. Researchers, list builders, the Enricher, the Checker, the Activity Collector, and the friend’s portal bots follow this file and no other rules doc. `docs/RULES_AUDIT.md` is a dated record of 2026-10-27. Files in `docs/archive/` are frozen copies of the old rule docs. They are not rules.

Scope until Alex says “roll out”: the 10 lab firms only (a16z, y-combinator, sequoia, lightspeed, generalcatalyst, plugandplay, accel, greenoaks, khosla-ventures, mio-partners).

Work order: build the Checker and the one home per kind, test on the lab firms, and only then clean up old bot tables. Cleanup is the last step, not the first.

The page snapshot further down describes what the live site drew on 2026-10-27. Where that snapshot disagrees with the rules in this section, the rules here win. The code has not been changed to match yet.

## Source ranking

Each fact has one source level. The level is a number.

1. **Official register.** SEC IAPD and Form ADV (including Item 5F), EDGAR Form D, a court record (CourtListener, PACER, uscourts.gov), a regulator (SEC, FINRA, FCA), a sanctions or screening register used inside its own check, GLEIF, Companies House, or another national registry. Level 1 is **Verified**. It may be shown.
2. **The firm’s own website.** The firm’s domain, not a search page and not a social post. Level 2 may be shown, and it is labelled as the firm’s own site.
3. **Elsewhere online.** News, newsletters, social posts, and any other page. Level 3 is held as **Unconfirmed** and is not shown.
4. **Nothing found.** Store “Not found yet” plus the search date. The row is kept and hidden.

If two sources disagree, the register wins. A firm site does not override a register. An elsewhere-online page does not override either, and it is not shown, except where the table below says that page part may show it.

A search-results page or a chat page is not a source at any level.

## Sources per page part

These rules override the general “elsewhere online is Unconfirmed” line for that part only. A dead link, a search page, or a chat page is still a failure. “Names the firm” means the copied text contains the firm’s name or short name.

| Page part | Shown | Held or failed |
|---|---|---|
| Reviews | A Reddit, X, or LinkedIn post that exists, names the firm, and is copied word for word with its link. The writer says they are a founder, or the profile shows that they are. | Anonymous, with no founder claim: Unconfirmed, not shown. A dead link or a post that does not name the firm: fail. |
| News | A story on TechCrunch, Reuters, Bloomberg, Axios, the Financial Times, the Wall Street Journal, CNBC, Forbes, or The Information, when the link opens and the story names the firm. | Any other blog or unknown site: Unconfirmed, not shown. A dead link, or a story that does not name the firm: fail. |
| Deals | The company’s own press release, or an SEC Form D. Both are level 2. The same known outlets as News are accepted. The amount and the Lead flag are filled only when that source states them. | Any other page: Unconfirmed, not shown. |
| Lawsuits | CourtListener, PACER, or uscourts.gov. These are level 1. | Any other page: Unconfirmed, not shown. |
| People | The firm’s team page or a Form ADV. The register is level 1. The firm’s team page is level 2. LinkedIn is allowed only for that person’s own job history. | Any other LinkedIn page, or a page that is not the team page or Form ADV: Unconfirmed, not shown. |
| Social counts | Only an account that is linked from the firm’s own website. | A count taken from anywhere else: Unconfirmed, not shown. |
| Portfolio and sectors | The portfolio company’s own website. That is level 2. | Any other site: Unconfirmed, not shown. |

## One way in

Every bot sends into the holding area `bots.research_submissions`. That includes researchers, list builders, portal-night-bot, the Activity Collector, the Enricher when it is only finding facts, and visitor requests. There is no side door. No hand fix. No one-off migration that writes a page table.

`bots.research_enrichments` can store a bot’s structured result. It is still holding. It is not a publish.

## The holding door

Only a known bot gets in, and each bot has its own key. Turning that key off stops that bot. The others keep working.

A bot may send as many distinct firms in an hour as the hourly limit. That limit is one setting, `door_hour_cap`. It starts at 100. Those firms are checked now. Further firms in that hour, up to three times the limit, are kept and wait until the next hour. They are not thrown away. More than three times the limit in an hour is an attack: that bot’s key is blocked, its waiting items are frozen, and Alex gets one alert. Only Alex can turn that bot back on. Changing the hourly limit changes the attack line with it. There is no second setting.

An exact copy is dropped at the door. It is not stored again.

The Checker works the queue oldest first. A bot whose items fail more than half the time, after at least 10 checked items in a day, is paused, and Alex gets one alert.

Failed holding items are kept 7 days. Processed uploads and search logs are kept 30 days.

## The Checker

The Checker is the entry check and the only publisher.

For each item it checks three things:

- The link is real. It is not a search or chat page, and it opens.
- The link matches the item (this firm, this person, this fund, this case).
- The source level, from the ranking above.

A register or firm-site item is published with the date and checked-by **Checker**. Those two values, and the source level, are stored on the item. They are not drawn on the page. An elsewhere-online item is held as Unconfirmed and is not shown, unless Sources per page part says that part may show it. A failure stays in holding with the reason. Failed items are kept 7 days, then removed. Nothing is re-checked unless Alex asks. The revision of social links and contact details every few months counts as that standing ask. News rows that already have a check mark stay checked. They are not re-checked in this pass.

The Enricher does not publish. The Activity Collector does not write `investments` directly.

## Three marks on every item

The Checker sets these once, on the item itself:

- **checked-on**, the date (`checked_on`)
- **checked-by**, the name Checker (`checked_by`)
- **source level**, 1, 2, 3, or 4 (`source_level`)

The columns are on the item tables: `press_item_firms`, `timeline_events`, `firm_check_rows`, `firm_people_roles`, `firm_profile_facts`, `firm_legal_items`, `reviews`, and `vc_source_facts`. They are not on `fact_sources`. A fact can have several source links, and press and the 10 checks do not keep the source pill in `fact_sources`.

`firm_check_rows.searched_at` and the news `check_mark` stay. They are not dropped. For the 10 lab firms, a search date is copied into `checked_on`. A news row already marked `checked_correct` or `checked_wrong` copies `last_checked_at` into `checked_on`, and the source level from the link. That copy is saved first in `marks_fold_backup`. A row the Checker did not check keeps `checked_by` empty. The page still reads the old fields.

`checked_on`, `checked_by`, and `source_level` are internal only. They are never shown on the live site, in any block. Alex rejected the Sequoia mockup that put a grey “checked &lt;date&gt;” next to the source pill. Do not build that.

## One home per data kind

| Kind | The one home | What gets merged in |
|---|---|---|
| Firm names | `firm_aliases`, with a type: display, legal, fund entity, or old name, plus the source | Gaps in `legal_name` |
| Funds | `funds` | `firm_profile_facts` where section is funds |
| AUM | one fact, regulatory assets from Form ADV Item 5F, with the as-of year | `firms.aum_display` |
| Deals and portfolio companies | `investments` and `portfolio_companies` | Timeline lines and collector rows that skip the Checker |
| News | one news item per normalized URL | `press_items` and `timeline_events` |
| Legal | `firm_legal_items` (this feeds checks 4, 6, and 7) | `regulatory_records` and `legal_matters` |
| People | `firm_people_roles` | `people` and `fund_people` |
| Reviews | `reviews` | Leftover `founder_accounts` |
| LPs | `firm_profile_facts` section `lps`, confirmed only | `bots.firm_lps` (holding until a confirmed row is published) |
| The 10 checks | `firm_check_rows` plus the findings in `vc_source_facts` | Stored pill text that does not match the findings |

Same-item keys: fund = fund name or SEC file number; news = normalized URL (lower case, no scheme, no `www.`, no query, no hash, no trailing slash); person = name plus kind; legal = case number or file number; LP = firm plus lowercased institution name; deal = firm plus company plus round.

The winner is the higher source level, then the newer date, then the more complete row. Every source is kept. The losing value is saved as a note. If two values still disagree, they go to the Checker review list. Each merged item gets one entry check. The merge log is permanent. The merge backup is kept 3 days, then deleted only with Alex’s OK.

On the 10 lab firms, exact copies in a home are the only rows removed. A different value stays on the page and is listed for the Checker. `fact_events` stays the public fact counter. The log is `home_merge_log`. The backup is `home_merge_backup`, and it is not deleted without Alex’s OK. `firm_aliases.alias_type` is display, legal, fund entity, or old name. The page does not read it.

A side row that has no home is backed up, then checked once. If the Checker publishes it, the row moves into its home. If the Checker does not, the row is deleted. Only the key (the URL, or the id when there is no URL), the kind, the firm, and the reason stay on `rejected_items`. The Checker will not add that key again. A legal-matter link is found by the matter id stored on the held log. That backup is `home_held_backup`. It is kept 3 days and is not deleted without Alex’s OK. The old tables themselves are not dropped.

## Live counts

Pills, section counts, tiles, and the counts on My firms are computed when the page is read. They are never stored. A stored pill that disagrees with the findings is wrong. Check 8 comes from the IAPD registration row, not from a hand-typed label.

## What the page shows

On the lab firms, once this is built:

- One latest fund tile, plus the line “N funds on SEC record · Show all”.
- One latest deal, plus Show all.
- One latest founder review, plus Show all.
- The latest 10 news items, plus Show all for the rest that are still on the page.
- Up to 20 people, plus Show all.

A deal row has a sector column, and a column that reads round · amount · Lead. Those three are filled only when a source states them. An empty amount stays empty.

Soft caps per firm: 500 news, 100 LPs, 200 deals. Past the cap, new items still come in and the oldest move to an archive file. Lawsuits, regulator actions, and negative news are never archived. One alert per firm when a cap is hit. Legal items and the 10 checks have no cap and are never archived or deleted. Only confirmed LPs are shown. A lead stays hidden.

These caps are not a license to delete. The archive file is the copy, and the row can be shown again from Show all.

## The 10 checks

There are exactly 10 checks. They are never merged with each other, and their searches are never merged.

| # | Check | What it is |
|---|---|---|
| 1 | Sanctions | Lists of people and companies you cannot do business with |
| 2 | Terrorism financing lists | Lists tied to funding terrorism |
| 3 | Export and investment restrictions | Trade and investment bans |
| 4 | Financial regulator actions | Fines, bans, and charges |
| 5 | Money laundering penalties | Anti-money-laundering enforcement |
| 6 | US court records | Federal and state cases |
| 7 | Court records worldwide | Cases outside the United States |
| 8 | Registration check | Investment-adviser registration, from the register |
| 9 | People behind the fund | Partners and owners, each checked against the lists above |
| 10 | Political ties | Government or political roles |

OpenSanctions is only one source, and only inside checks 1, 2, and 10. It is not a source for the other checks, and it does not replace a register those checks have of their own. Checks 3, 4, 5, 6, 7, 8, and 9 keep their own searches. A same-name hit that is not the same person is not a finding.

## Search and new firms

Search matches the display name, the legal name, fund names, and the website. Those names live on `firm_aliases` with a type. `firm_suggest` already reads aliases. There is no second search table.

A new firm is deduped by registry id first (SEC CRD, FCA, Companies House, another national regulator, or a GLEIF LEI). If there is no registry id, match on domain plus name plus HQ, and mark the firm **no registry ID**.

## How long rows are kept

Search logs and uploads that have been processed are kept 30 days. Failed holding items are kept 7 days. The merge log is kept. Legal items and the 10 checks are not deleted by a retention job.

## What the live code still does

These are conflicts with this guide. They are not permissions.

- `toxy-enricher` still publishes at ingest for a firm that is not one of the 10 lab firms. On those 10, enrich lands in holding and the Checker publishes.
- The Activity Collector wrote Y Combinator investments straight into `investments`.
- One-off migrations wrote Sequoia’s `$82.2B`, Sequoia’s 10 deals, and the news check marks.
- Press and timeline are still two tables. The page merges some of them only in the browser.
- `bots.firm_lps` and `firm_profile_facts` both hold LP names. Confirmed LPs on the profile table are the page home.
- Pills and some counts are stored. This guide says they are computed.
- The ingest reply still names `docs/DATA_RULES.md`. That string is code, not a rule.
- `docs/data-model.md` still describes `legal_matters` and a score on the page. It is not a rulebook.
- There is no prompt file for the Activity Collector or the list builders except this guide and `docs/BOTS.md`.

---

# Page snapshot, 2026-10-27

This snapshot is what the live page returned that day. It is not a second set of rules.

The live firm page is filled in the browser. `firm_page` returns the payload. `launch/js/company.js` draws it. `launch/copy.json` holds the labels. A fetch of `https://regretamin.com/vc/sequoia/` returns the shell; the figures below are from calling `firm_page('sequoia')` and `firm_page` field lists, plus the a16z counts from the same tables.

The problem numbers point at the dated record `docs/RULES_AUDIT.md`.

## What Sequoia’s payload contains

`firm_page('sequoia')` returned `open: true` (the paywall switch is off).

- Name: Sequoia Capital. HQ: Menlo Park, CA. Website: sequoiacap.com. Assets string: `$82.2B`.
- Hero facts that still exist in the payload: HQ, and Regulatory AUM `$82.2B`. The hero cards are not drawn.
- Sections returned: overview 4, checks 10, legal 6, press 5, people 15, funds 9, timeline 1. No LP section and no founders section.
- The browser drops `checks` from the full-report section list and combines press and timeline into News.
- Activity: active, 10 deals in the last 12 months, 10 deals total, latest fund Sequoia Capital Fund, L.P. at $22.7B, latest deal Blacksmith, 8 public founder reviews.

a16z, from the same tables: 13 people shown, 26 legal rows shown, 81 investments, 11 of 21 reviews public, 87 check-detail facts, one current score row that the page does not draw.

## Who collects what

| Bot | What it is allowed to do | Where it lands |
|---|---|---|
| List builders | Choose firms for the queue. No written method. | `research_queue.list_source` |
| Researchers (`toxy-researcher-*`) | Send a dump. It does not write the page. | `bots.research_submissions` |
| Researcher 3 | Paid checks and visitor requests first. | same, plus `ondemand_jobs` |
| Enricher (`toxy-enricher`) | The only bot that publishes a page, at ingest. | `bots.research_enrichments`, then the page tables |
| Checker | Named in `docs/DATA_RULES.md`. No separate publish path. | holding area |
| Activity Collector | Filled Y Combinator investments (`source_system = activity_collector_2026_10_25`). No written spec. | `investments`, `portfolio_companies` |
| Friend’s `portal-night-bot*` | Can submit dumps. Feedback text is only attached for that bot. Does not publish. | holding area |
| One-off migrations | Sequoia’s `$82.2B`, Sequoia’s 10 deals, press and timeline check marks. | the named tables |

Sites the rules name: sec.gov (IAPD / Form ADV, including Item 5F, and EDGAR Form D), CourtListener, PACER, uscourts.gov, FINRA, the FCA, OFAC and `sanctionssearch.ofac.treas.gov`, the UK sanctions list, `sanctionsmap.eu`, the UN list, GLEIF, Companies House. OpenCorporates is not named. Firm sites, TechCrunch, Bloomberg, Reuters, and Axios appear as real lab URLs. X and LinkedIn appear as review sources in the gold examples.

There is no written rule that a given element must come from a given site, except the source filter (sec.gov and courts for government hosts; search pages refused).

## 1. Site logo and wordmark

1. The Regretamin lockup in the corner. It is not the firm’s logo.
2. A static file. No table.
3. Designed asset. No bot.
4. No data rule.
5. Always shown.
6. No problem found (RULES_AUDIT 5).

## 2. Search box and suggestions

1. The box on the home page, the firm page, and the empty state. After a short pause it lists up to 8 firms. Choosing one opens `/vc/<slug>/`. No match offers “Request this firm.”
2. `firm_suggest` reads `firms.display_name`, `firms.name`, `firms.short_name`, `firms.slug`, `firms.hq`, and `firm_aliases.alias`. It returns slug, display name, short name, and HQ. `launch/js/search.js` calls it.
3. Names arrive when a firm is created from the queue or merged (`docs/DEDUPE.md`, `docs/FIRM_REQUESTS.md`). List builders and visitor requests fill the queue. The enricher creates the page.
4. Only published, non-test, real, not-deleted firms. Match is a substring. A prefix ranks first. Aliases are included. Legal name is not a separate column in the search; it is searchable only if it was copied into `firm_aliases`.
5. A deleted or unpublished firm is absent.
6. Lab display names match `firms.name` (RULES_AUDIT 1). Sequoia has no legal name to alias (RULES_AUDIT 2). 4,025 queue rows have no `list_source` (RULES_AUDIT 23).

## 3. Firm header

1. The large name, then a meta line: HQ, short name, and the website. Sequoia shows “Sequoia Capital” and “Menlo Park, CA.”
2. `firm_page` builds `firm.name` from `coalesce(display_name, name)`, `firm.sec_name` from `coalesce(legal_name, name)`, `firm.short_name`, `firm.hq` from `firm_hq_format`, `firm.website` from the primary domain, `firm.assets` from `_firm_assets`. The meta line in `company.js` `metaLine` prints HQ, short name, and the website. It does not print the legal name.
3. HQ and the website start on the queue row (list builder or request). The enricher can publish an overview fact labelled Headquarters. Display name is cleaned by `firm_display_name` when the page is created.
4. No written rule that HQ must be a city from IAPD. The queue stores `hq_city`, `state`, and `country`.
5. The header shows whenever the page loads. Hero cards (staff, founded, AUM as cards) were removed and are not drawn.
6. Legal name gaps: RULES_AUDIT 2. Slug: no problem (RULES_AUDIT 4).

## 4. SEC fact pills

1. Small links under the header for hero facts whose source is sec.gov, except HQ. At most 7. AUM and “fund gross assets” are labelled differently.
2. `firm_page` hero list: `firm_profile_facts` where `hero_label` is set and a `fact_sources` row exists. `company.js` `secPills` keeps only a sec.gov source.
3. The enricher, from a Form ADV on sec.gov / adviserinfo.sec.gov. Item 5F is the assets figure the helper looks for.
4. The fact needs a source or it is not in the hero list. The pill needs the host to be sec.gov.
5. Hidden when the hero list is empty or no source is sec.gov.
6. The assets helper can drop the unit (RULES_AUDIT 11). Overview paragraphs can still contain a CRD that these pills do not show (RULES_AUDIT 15).

## 5. Score bar

1. The visitor does not see a score. There is no score block in `company.js`.
2. `score_results` (current row), `score_inputs`, and `score_result_parts` still exist. `vc_scores` still exists. Neither is read by `firm_page`.
3. Unknown for the stored rows. The formula in `score/` is a copy of the old site and is not run on publish. No bot recomputes it.
4. The written formula is `docs/toxy-score-v2-rules.md`. It is not enforced on the live page.
5. Nothing shows it. Nothing hides it. It is not in the layout.
6. RULES_AUDIT 21. Five lab firms have a stored current score, including a16z.

## 6. Activity strip

The strip sits above the sections. It is omitted when there is no tile, no deal, and no review.

### 6a. “Active” tile

1. A tile when the firm has a deal or a fund close in the last 365 days. Sequoia is active.
2. `investments.invested_on` and `funds.closed_on`, both `data_status = real`. `_firm_activity`.
3. Sequoia’s deals were copied from timeline lines (`sequoia_timeline_deals`). Other deals: unknown, except Y Combinator’s activity collector.
4. The 365-day window is display math, not a collect rule.
5. The tile is absent when both counts are zero.
6. RULES_AUDIT 12.

### 6b. Deals in the last 12 months

1. A count. Sequoia: 10.
2. `investments` where `invested_on` is within 365 days and `data_status = real`.
3. Same as 6a.
4. No required fields beyond the row existing. Amount can be empty.
5. The tile is omitted when the count is 0.
6. RULES_AUDIT 12. Six lab firms are at 0.

### 6c. Latest fund tile

1. The newest fund that has a raised amount, with the name, the amount, and a filing link. Sequoia: Sequoia Capital Fund, L.P., $22.7B, 5 Feb 2026.
2. First choice: `funds.raised_usd` or `funds.size_usd`, `funds.name`, `funds.closed_on`, `funds.filing_url`. On the 10 lab firms, if that amount is missing, `earlierFund` reads a Funds section line shaped “Name · $amount · date.” If that is also missing, the assets tile is used.
3. Sequoia’s two amounts were written by the one-off migration from EDGAR Form D. Other `funds` rows: unknown, often older imports. Profile-fact fund lines: the enricher, from Form D or Form ADV.
4. The tile skips a $0 amount. It skips lines that look like AUM or gross assets.
5. Other firms, outside the 10, still show a fund with no amount.
6. RULES_AUDIT 10. Lightspeed has 64 fund rows and 4 profile lines. Accel has profile lines and no `funds` row.

### 6d. Assets under management tile

1. Shown on the 10 lab firms only when no fund amount is available. Label “Assets under management.”
2. Hero fact whose label maps to Regulatory AUM, else `firm.assets` from `_firm_assets`. The helper reads a profile fact that cites Item 5F or “regulatory AUM,” skips Schedule D gross assets, and otherwise uses `firms.aum_display` when it starts with `$`.
3. SEC Form ADV Item 5F, via the enricher. Sequoia’s display string was set by the one-off migration to `$82.2B`.
4. A new AUM fact must contain a digit. The helper does not keep a trailing B, M, or K.
5. Hidden when both the hero and the helper are empty.
6. RULES_AUDIT 11. Four lab firms have a null helper result. Greenoaks returns `$18.27`.

### 6e. Latest deal, and “Show all”

1. Company, round, date, and source host. Sequoia’s latest is Blacksmith. “Show all” opens the rest. Sequoia has 10.
2. `investments` joined to `portfolio_companies.name`. Source is the first http(s) URL in `investments.source_urls`. `firm_activity_list` loads the full list.
3. Lab timeline regex, the Sequoia copy, or the activity collector. Press and Form D are not wired as a general deal writer.
4. `data_status = real`. No check that the round is a short name. Sorted by date.
5. The block is omitted when there is no deal. The full list waits until the page is open. The lock is off, so it is open.
6. RULES_AUDIT 12 and 13.

## 7. The 10 checks

1. A table: number, title, pill, what was found, date searched. A row opens the findings. Pills are Clear, Review, Worth knowing, or Not checked yet. A stored `red` is drawn as Review. While a bot holds the claim, the first unfinished row says “Checking” and the rest say “Waiting.”
2. `firm_check_rows`: `n`, `title`, `descr`, `state`, `count_label`, `searched_at`. Findings on an open page are `firm_page` `checks[].items`, backed by `firm_details` (`vc_source_facts`) and, when those are missing, the check’s itemized findings. Name-only hits are `checks[].name_only`.
3. Titles were inserted when the firm was created, or by the hand migration `20261023230000_sync_checks_all_launch_firms.sql`. Evidence, when it exists, came from researcher dumps into `vc_source_facts` (SEC, courts, sanctions lists). New dumps no longer copy onto this table. No bot currently updates the pill.
4. A new firm’s pills are `nc`. `launch/checks.py` can derive a pill and is not what the page runs. Name-only text is excluded inside `firm_details`.
5. The table shows on the summary view. “Not checked yet” has no “nothing found” line. The date shows only when `searched_at` is set.
6. RULES_AUDIT 20 and 16.

### Check 1. Sanctions

1. “Government lists of people and companies you can’t do business with.” The muted line says “Searched government sanctions lists.” It does not name OFAC SDN.
2. Pill: `firm_check_rows` n=1. A screening row, if any, is `sanctions_checks` or a `vc_source_facts` row whose field is `sanctions`. The page does not join those itself; it shows whatever was stored on the pill and in `firm_details`.
3. Intended sources, from `docs/SOURCE_TIERS.md`: OFAC, `sanctionssearch.ofac.treas.gov`, treasury.gov, the UK sanctions list, `sanctionsmap.eu`, the UN list. Which bot ran them for a given Clear pill: unknown. The enricher is told not to file a same-name hit as a legal item.
4. A same-name hit stays Clear and adds the muted sentence from `copy.json` `name_only`. There is no required list name.
5. The pill shows the stored state. Nobody rechecks it when `sanctions_checks` is empty.
6. RULES_AUDIT 6. Five lab firms are Clear with 0 `sanctions_checks` rows. Accel is one.

### Check 2. Terrorism financing lists

1. “Lists of people and groups linked to funding terrorism.”
2. `firm_check_rows` n=2. Detail, when present, is a `vc_source_facts` field `terrorism_lists`.
3. No written list of sites beyond “government lists.” Unknown which bot last set the lab pills.
4. No required fields beyond the pill row.
5. Same as check 1.
6. Same gap as RULES_AUDIT 20: the pill is not recomputed.

### Check 3. Export and investment restrictions

1. Trade and investment bans. The enricher doc uses ITAR / the DTC debarred list as the example for a name-only hit on this check.
2. `firm_check_rows` n=3. Detail field `export_restrictions`.
3. `trade.gov` is the example in `docs/ENRICHER.md`. No written rule that it must be that site.
4. Name-only hits stay Clear.
5. Same as check 1.
6. RULES_AUDIT 20.

### Check 4. Financial regulator actions

1. “Fines, bans and charges from financial regulators.” a16z’s stored count is “1 open probe.”
2. Pill: `firm_check_rows` n=4. Detail: `vc_source_facts` regulatory actions, and `firm_legal_items` whose group is `regulator` (sec.gov, FINRA, fca.org.uk). `regulatory_records` is a third table the section does not read.
3. SEC, FINRA, FCA, and DOJ mentions inside legal facts. Enricher for new legal items. Older facts from researcher dumps.
4. A new allegation needs a court or regulator document on the 10 lab firms or it is rejected.
5. The pill is the stored state, not a count of regulator rows.
6. RULES_AUDIT 8. MIO’s pill says 2 actions while `regulatory_records` is 0.

### Check 5. Money laundering penalties

1. Anti-money-laundering fines.
2. `firm_check_rows` n=5. Detail field `aml_penalties` or `adv_disclosures`.
3. Unknown site list. No written rule.
4. No extra validation.
5. Stored pill.
6. RULES_AUDIT 20.

### Check 6. US court records

1. Federal and state cases. Active cases sort first in the detail.
2. Pill: `firm_check_rows` n=6. Detail: `vc_source_facts` legal matters for the firm, and `firm_legal_items` group `case`. Status words (active, terminated, settled) are read in `company.js` `caseStatus`.
3. CourtListener, PACER, uscourts.gov. The enricher sets group `case` when the source host is one of those, plus Justia, Law360, and Casetext.
4. Leads are held. The legal key dedupes on a case number and misses a “Lead” prefix.
5. A count with no itemized rows says details are coming and links a CourtListener search of the legal name.
6. RULES_AUDIT 7.

### Check 7. Court records worldwide

1. Cases outside the U.S. A non-party mention can be the count.
2. `firm_check_rows` n=7. Detail field `courts_worldwide`, plus legal facts whose text looks non-US.
3. No written court list. Unknown bot for the stored pills.
4. No extra validation.
5. Stored pill.
6. RULES_AUDIT 20.

### Check 8. Registration check

1. “Registered with the regulator as an investment adviser, and active.”
2. `firm_check_rows` n=8. The overview Registration line is a different element, drawn from profile facts, not from this pill.
3. SEC IAPD / Form ADV. Enricher for the overview line. The pill itself is not updated by that publish.
4. The overview draw shortens the sentence to “SEC-registered since <year>, active” or the exempt-reporting line. The pill does not use that sentence.
5. Lightspeed and others can show “Not checked yet” here even when an overview registration line exists.
6. RULES_AUDIT 8 and 20.

### Check 9. People behind the fund

1. Partners and owners, each checked against the lists above.
2. `firm_check_rows` n=9. Detail field `people_screen`, or a legal fact whose entity starts with `partner:`.
3. The people themselves are Form ADV Schedule A, via the enricher, into `firm_people_roles`. The screening of those people is a different store. Unknown which bot screened them.
4. A person publish checks the name. It does not set this pill.
5. Stored pill.
6. RULES_AUDIT 9 and 20. Accel’s Schedule A sentences were hidden as people and did not become a check.

### Check 10. Political ties

1. People at the firm who held government or political roles. Worth knowing when a hit is a partner.
2. `firm_check_rows` n=10. Detail field `pep`.
3. No written registry. Unknown bot.
4. A surname-only line is not a name-only flag (`docs/ENRICHER.md`).
5. Stored pill. a16z is Worth knowing from the hand migration.
6. RULES_AUDIT 20.

## 8. Overview

1. Rows in a fixed order: HQ, Legal name, Registration, Founded, Owners, Recent changes, then anything else that was not hidden. Sequoia returns 4 overview items before that rewrite.
2. `firm_profile_facts` where `section = overview`, not hidden, with a source. `company.js` `overviewRows` rewrites them while drawing.
3. Enricher, from Form ADV and the firm’s own pages. Labels in the gold example include Headquarters.
4. One label, one value, one source. Headquarters, Founded, and Regulatory AUM conflict instead of duplicating when the value differs. Notes and over-long text are rejected for new items.
5. Hidden labels: Other names, Type, Staff, Private funds, Legal entity, Sanctions screening, empty, “Not found.” A row with no source is not returned.
6. RULES_AUDIT 15. The label `Overview` is not hidden. Eight lab firms have 3 such paragraphs each.

## 9. Firm & funds

1. One row per stored fund fact: name, amount, date, source pills. Sequoia returns 9.
2. `firm_profile_facts` `section = funds`. Not the `funds` table. That table feeds the activity tile.
3. Enricher, from EDGAR Form D and Form ADV Schedule D. Sequoia’s tile amounts were a one-off from two Form D filings.
4. Name required. Amount, when present, is a number. Dedupe is the fund name or the fund key.
5. Hidden rows and rows with no source are omitted. Sequoia’s raw Item 5F lines were hidden by the one-off migration.
6. RULES_AUDIT 10.

## 10. Limited partners

1. One card per LP name. Several commitments become one card with a count. Sequoia’s payload has no LP section, so the block is omitted.
2. `firm_profile_facts` `section = lps`. Label is the institution. Value is the type, fund, amount, and status text. `bots.firm_lps` is not read.
3. Profile rows: the enricher, from public filings and LP reports (the gold example says so; the exact site is whatever URL was sent). Bot rows: a researcher dump, often pensions and Form D related parties. Exact registry for each Accel LP: the row’s `source_url`. Not re-fetched for this guide.
4. Profile: name required, type optional, source required. Bot table: name, status confirmed or lead, URL, type from a fixed list, cap 100, unique on name plus fund.
5. A lead value is relabelled “Not confirmed” and still shown. No source, or hidden, drops the row.
6. RULES_AUDIT 22. 33 names are in both homes. Accel’s Adams Street row is the example.

## 11. People and board seats

1. Cards grouped into board, moves, and officers. Sequoia returns 15 people.
2. `firm_people_roles`: `person_name`, `role`, `kind`, not hidden, with a source. The older `people` and `fund_people` tables are not this section.
3. Enricher, typically Form ADV Schedule A (officers) and board seats from filings or the firm site. The gold example uses the IAPD PDF.
4. One person per name. Same person and kind with the same role adds the source. A different officer role is a conflict. The note guard hides Schedule A blobs.
5. Hidden rows are omitted. The browser also refuses note-like text.
6. RULES_AUDIT 9. Greenoaks still shows “Board seat: Neil Mehta…”.

## 12. Legal and regulatory section

1. Rows with a title, a year, a status, and source pills. Cases, then regulator rows, then context. Sequoia returns 6.
2. `firm_legal_items`, not hidden, with a source. Group, title, year, status, note. This is separate from the 10-check details.
3. Enricher. Court hosts become `case`. sec.gov, FINRA, and the FCA become `regulator`. Anything else becomes `context`.
4. Title required. An allegation is held. Lab allegations need a court or regulator URL.
5. Hidden or unsourced rows are omitted. “Lead” in the title is not a hide rule.
6. RULES_AUDIT 7 and 8.

## 13. News

1. One list, newest first, since 2023. A card has a headline, a date, outlet pills, and a tag such as Court or Fund when the timeline item had one. Sequoia’s payload has 5 press rows and 1 timeline row. The browser may merge some of those into fewer cards. That merge is not stored.
2. Press: `press_items` plus `press_item_firms` where `check_mark = checked_correct` and the URL is non-empty. Timeline: `timeline_events` where `check_mark = checked_correct`, not hidden, and a source URL or a `fact_sources` link exists. `company.js` `buildNews` unions them.
3. Enricher. Press is an outlet story (TechCrunch, Bloomberg, Reuters, and the firm’s own post are real lab examples). Timeline is an event (a filing, a raise, a court date). The bot chooses which section. There is no classifier.
4. Press needs outlet, headline, and URL. Timeline needs a date and an event. Publish dedupes press by the exact URL and timeline by date plus text. It does not compare the two tables. Display normalizes the link and groups headlines that share an event word and a name within 7 days.
5. `checked_wrong` and `not_checked` stay stored and are not drawn. Dates before 2023 are not drawn. Own-site links are labelled “Own media.”
6. RULES_AUDIT 14. 13 lab links are in both tables. New rows stay off the page until a person sets `checked_correct`. The lab marks were set by `20261027221100_news_one_list_data.sql`, not by a bot.

## 14. What founders say, and the review cards

1. Two places. A “What founders say” section is drawn when `founder_accounts` still has rows that were not moved. Sequoia has no such section. The activity strip shows the latest public founder review, and “Show all” lists the rest. Sequoia’s count is 8.
2. The strip reads `reviews`: author, role, company, round, body, date, ratings, source URL, type. Filter: founder, public, approved. Moved `founder_accounts` rows are excluded from the old section.
3. Enricher “What founders say” items are written to `reviews`. Gold examples use LinkedIn and similar posts. A visitor form can also insert a review, which starts pending. The activity collector is not documented as a review writer.
4. One person in `who`, a quote, a source. Same URL or same quote text merges. Own-site quotes are not called independent.
5. Pending, non-public, or non-founder rows are not drawn. No written owner for who approves a bot quote.
6. RULES_AUDIT 19. Khosla has 4 stored and 0 shown.

## 15. Source pills

1. The grey links under a row: label, date, and the URL. News cards also list outlets.
2. `fact_sources` joined to `sources`, via `_src`. Press uses the article URL itself. Timeline uses `source_url` when it is set, otherwise `fact_sources`.
3. Whatever URL the bot sent, if it passed the source filter. Trusted hosts are the allowlist in `trusted_source_domains` plus government and court hosts (`docs/SOURCE_TIERS.md`).
4. Search and chat URLs are refused at ingest. A fact with no usable source is flagged `needs_source` and hidden.
5. A section row with an empty source list is not returned, except press and the check pills.
6. RULES_AUDIT 17 (no unsourced lab profile facts) and 18 (the pill does not say trusted or other).

## 16. Home page

1. The headline, the search box, and the marketing text. It does not list firms or scores.
2. `launch/copy.json` and `launch/build.py`. No firm table on that screen.
3. No bot.
4. No data rule.
5. Always the same shell. Firm data appears only after a search.
6. No problem found for a missing firm grid, because the current home page is not a directory. Older docs that describe a scored homepage are old (RULES_AUDIT O5).

## 17. Account, credits, and My firms

1. Account shows the plan, credits left, and renewal. My firms lists saved and checked firms with HQ and pill counts. It does not show a score or a legal name.
2. `my_account` reads `check_balances` (plan, free left, paid left, period end). `my_firms` reads `watchlist`, `check_events`, `firms.name`, `firms.short_name`, `firms.hq`, and counts from `firm_check_rows`.
3. Credits come from signup, Stripe, and the yearly refill cron. Saved firms are the visitor’s watchlist. Checked firms are spend events.
4. The yearly refill runs hourly. Lapsed plans are downgraded hourly. The on-demand tick refunds a paid check that is not done in 24 hours. The lock is off, so opening a lab page does not spend a credit.
5. These pages require a signed-in session. Firm facts are not repeated here.
6. `my_firms` uses `firms.name`, which matches `display_name` on all 10 lab firms (RULES_AUDIT 1 and C12b). The on-demand doc still describes a locked page (RULES_AUDIT K5).

## 18. Paywall and “email me”

1. With the lock off, the firm page opens, including News, legal, and the checks. The “email me when it’s ready” box is for a firm that still needs research, and only while signed out.
2. `app_settings.lock_enabled`. Live value `false`. The box writes `research_requests` / `ondemand_jobs` through `unlock_firm` and `notify_when_checked`.
3. No bot writes the switch. Researcher 3 claims the paid lane.
4. A finished firm does not re-enter the paid lane. Rate limits live on visitor requests (`docs/FIRM_REQUESTS.md`).
5. The switch hides the lock. It does not hide bad rows.
6. RULES_AUDIT A31 and K5. `docs/ON_DEMAND.md` still tells the visitor they must spend a credit.

## 19. Elements that are easy to look for and are not on the page

- A firm logo. Not stored for the header.
- A score bar. Stored for some firms, not drawn.
- OFAC SDN named on the sanctions row. Not in the copy.
- OpenCorporates. Not in the source rules.
- `bots.firm_lps` and `regulatory_records` and `legal_matters`. Present in the database, not what these sections read.
