# Page data guide

Rule ids (A1.2, B6c.3, C8.4) are stable. `docs/rules_index.csv` lists every rule id with its section and status.

## Contents

- [P. About this file](#p)
- [A. How data comes in](#a)
  - [A1. Source ranking](#a1)
  - [A2. Sources per page part](#a2)
  - [A3. One way in](#a3)
  - [A4. The holding door](#a4)
  - [A5. The Checker](#a5)
  - [A6. Three marks on every item](#a6)
  - [A7. One home per data kind](#a7)
  - [A8. Live counts](#a8)
  - [A9. List limits and archiving (the one table)](#a9)
  - [A10. Search and new firms](#a10)
  - [A11. How long rows are kept](#a11)
  - [A12. Shared checks list](#a12)
- [B. The page](#b)
  - [B1. Site logo and wordmark](#b1)
  - [B2. Search box and suggestions](#b2)
  - [B3. Firm header](#b3)
  - [B4. SEC fact pills](#b4)
  - [B5. Score bar](#b5)
  - [B6. Activity strip](#b6)
    - [B6a. “Active” tile](#b6a)
    - [B6b. Deals in the last 12 months](#b6b)
    - [B6c. Latest fund tile](#b6c)
    - [B6d. Assets under management tile](#b6d)
    - [B6e. Latest deal, and “Show all”](#b6e)
  - [B7. Thesis (replaces Overview; Alex, 2026-10-28)](#b7)
  - [B8. Firm & funds](#b8)
  - [B9. Limited partners](#b9)
  - [B10. People and board seats](#b10)
  - [B11. Legal and regulatory section](#b11)
  - [B12. News](#b12)
  - [B13. What founders say, and the review cards](#b13)
  - [B14. Source pills](#b14)
  - [B15. Home page](#b15)
  - [B16. Account, credits, and My firms](#b16)
  - [B17. Paywall and “email me”](#b17)
  - [B18. Elements that are easy to look for and are not on the page](#b18)
- [C. The 10 checks](#c)
  - [C0. How the checks work](#c0)
  - [C1. Sanctions](#c1)
  - [C2. Terrorism financing lists](#c2)
  - [C3. Export and investment restrictions](#c3)
  - [C4. Financial regulator actions](#c4)
  - [C5. Money laundering penalties](#c5)
  - [C6. US court records](#c6)
  - [C7. Court records worldwide](#c7)
  - [C8. Registration check](#c8)
  - [C9. People behind the fund](#c9)
  - [C10. Political ties](#c10)
- [R. Removed (kept for history)](#r)
  - [R1. What the live code still does](#r1)
  - [R2. Page snapshot, 2026-10-27](#r2)
  - [R3. Who collects what (snapshot 2026-10-27)](#r3)
  - [R4. Overview (old, being removed)](#r4)
  - [R5. Old notes](#r5)

<a id="p"></a>
## P. About this file

- **P.1** This is the only rulebook. Researchers, list builders, the Enricher, the Checker, the Activity Collector, and the friend’s portal bots follow this file and no other rules doc. `docs/RULES_AUDIT.md` is a dated record of 2026-10-27. Files in `docs/archive/` are frozen copies of the old rule docs. They are not rules.
- **P.2** Scope until Alex says “roll out”: the 10 lab firms only (a16z, y-combinator, sequoia, lightspeed, generalcatalyst, plugandplay, accel, greenoaks, khosla-ventures, mio-partners).
- **P.3** Work order: build the Checker and the one home per kind, test on the lab firms, and only then clean up old bot tables. Cleanup is the last step, not the first.
- **P.4** The snapshot items (.1 to .6 in Parts B and C) describe what the live site drew on 2026-10-27. Where a snapshot item disagrees with the rules in Part A, the rules in Part A win. The code has not been changed to match yet.

<a id="a"></a>
# A. How data comes in

<a id="a1"></a>
## A1. Source ranking

- **A1.1** Each fact has one source level. The level is a number.
- **A1.2** **Official register.** SEC IAPD and Form ADV (including Item 5F), EDGAR Form D, a court record (CourtListener, PACER, uscourts.gov), a regulator (SEC, FINRA, FCA), a sanctions or screening register used inside its own check, GLEIF, Companies House, or another national registry. Level 1 is **Verified**. It may be shown.
- **A1.3** **The firm’s own website.** The firm’s domain, not a search page and not a social post. Level 2 may be shown, and it is labelled as the firm’s own site.
- **A1.4** **Elsewhere online.** News, newsletters, social posts, and any other page. Level 3 is held as **Unconfirmed** and is not shown.
- **A1.5** **Nothing found.** Level 4 is **Nothing found**: store “Not found yet” plus the search date. The row is kept and hidden. Levels 1–4 match [A6.1](#a6) (Alex, 2026-10-28).
- **A1.6** If two sources disagree, the register wins. A firm site does not override a register. An elsewhere-online page does not override either, and it is not shown, except where the table in [A2](#a2) says that page part may show it.
- **A1.7** A search-results page or a chat page is not a source at any level.
- **A1.8** Exception (Alex, 2026-10-28): the latest fund amount (money raised for the latest fund only) may come from an approved news outlet or another trusted site the project uses (`trusted_source_domains`), not only from SEC Form D. That source must state the amount. It is shown, not held as Unconfirmed. If sources disagree, the SEC record wins.

<a id="a2"></a>
## A2. Sources per page part

- **A2.1** These rules override the general “elsewhere online is Unconfirmed” line for that part only. A dead link, a search page, or a chat page is still a failure. “Names the firm” means the copied text contains the firm’s name or short name.

| Rule |  Page part | Shown | Held or failed |
|---|---|---|---|
| **A2.2** | Limited partners (LPs) | Any trustworthy source (Alex, 2026-10-28): pension or endowment reports, public filings, approved news outlets or other sites in `trusted_source_domains`. The link must open and name the LP and the firm or fund. The link is kept. Shown as one line per LP: name and the total amount across all its funds with this firm that we have, for example "CalPERS · $150M (3 funds)". The fund count in brackets is shown only when the LP is in 2 or more funds; with 1 fund, no brackets. An amount only when a source states it, else just the name. No type, year or status on the page. Status (confirmed or lead) is kept in the system only (Alex, 2026-10-28). | Junk, anonymous or untrusted sites, a dead link, or a page that does not name both: fail. |
| **A2.3** | People and interviews | People: only current people at the firm are shown; people who left are not shown, and neither are their interviews (Alex, 2026-10-28). Each current person may have up to 10 interviews: YouTube videos or press coverage, shown as link + headline. The 10 shown are the ones with the most views (YouTube); press coverage, which has no view count, comes after, newest first. More than 10: the rest are stored, not shown. The link must open and show that person. Design comes later, mockup first. People sources: the firm’s team page or a Form ADV. The register is level 1. The firm’s team page is level 2. LinkedIn is allowed only for that person’s own job history. | A dead link, a page that does not show that person, or a person who left: not shown. Any other LinkedIn page: not used. For people’s names and roles only, a page that is not the team page or Form ADV is Unconfirmed, not shown; interviews from YouTube or the press stay allowed as above (Alex, 2026-10-28). |
| **A2.4** | Legal cases (display, Alex 2026-10-28) | Source (Alex, 2026-10-28): CourtListener, PACER, uscourts.gov, a regulator (SEC, FINRA, FCA), Justia, Law360, or Casetext; a link is required. Each case shows pills: status (Active, Closed, Settled, Dismissed), side (Defendant or Plaintiff), and what it is about (fixed list: Fraud, Contract, Employment, Securities, Regulator action, IP). Also: other party, filed year (and closed year if any), court or regulator (e.g. SEC, N.D. Cal.), and the required link. A Settled case also shows the settlement terms (for example the amount) when the court or regulator record states them; otherwise nothing is added. The page shows 10 legal items (cases and regulator actions), active first, then the rest by most recent, plus Show all (Alex, 2026-10-28). This replaces "last 2". A legal mention or context row about an existing case is attached to that case as an extra link (for example "In the news: Reuters"); it is not its own row and is not counted. A mention with no matching case is not shown; it stays as a lead for the check. Show all opens every case. No cases at all: the section is not shown, no empty message. | No link from the allowed legal sources: not shown. |
| **A2.5** | Reviews | A post on any public site (for example Reddit, X, LinkedIn, YouTube, Medium, a blog or podcast page; Alex, 2026-10-28) that exists, names the firm, and is copied word for word with its link. The writer says they are a founder, or the profile shows that they are. | Anonymous, with no founder claim: Unconfirmed, not shown. Glassdoor and other employee reviews: not used. A dead link or a post that does not name the firm: fail. |
| **A2.6** | News | A story on TechCrunch, Reuters, Bloomberg, Axios, the Financial Times, the Wall Street Journal, CNBC, Forbes, or The Information, when the link opens and the story names the firm. | The firm’s own site posts or blog: never shown in News (Alex, 2026-10-28). Any other blog or unknown site: Unconfirmed, not shown. A dead link, or a story that does not name the firm: fail. |
| **A2.7** | Deals | An SEC Form D (level 1) or the firm’s press release (level 2) (Alex, 2026-10-28). The same known outlets as News are accepted. The amount and the Lead flag are filled only when that source states them. | Any other page: Unconfirmed, not shown. |
| **A2.8** | Lawsuits | Merged into A2.4: allowed sources are the list in [A2.4](#a2) only (Alex, 2026-10-28). CourtListener, PACER, uscourts.gov and regulators are level 1. | Any other page: Unconfirmed, not shown. |
| **A2.10** | Social counts | Only an account that is linked from the firm’s own website. | A count taken from anywhere else: Unconfirmed, not shown. |
| **A2.11** | Sectors (portfolio and deals, one rule) | Any source is accepted (approved by Alex on 2026-10-28). The link must be a real page that opens and must describe that startup. A 403 or block page counts as opened, with a note. The sector is only ever the value the record gives, never invented. | A dead link, a search page, a chat page, an invented link, or a page that does not describe the startup: fail. |
| **A2.12** | Funds | SEC filings (Form D, Form ADV), else an approved news outlet or a trusted site (per [A1.8](#a1)). The link is kept. (Alex, 2026-10-28) | Any other page: Unconfirmed, not shown. |
| **A2.13** | Header HQ | The firm’s IAPD record, else the firm’s own website. (Alex, 2026-10-28) | Any other page: not used for HQ. |
| **A2.14** | Header website | The firm’s own site, checked that it opens and belongs to the firm. (Alex, 2026-10-28) | A site that does not open or does not belong to the firm: not shown. |
| **A2.15** | Founded year | The firm’s own site or a company register (a US state registry, Companies House). The link is kept. Stored in `firms.founded_year`; not shown until a header mockup is approved. The SEC registration date is not the founded year. (Alex, 2026-10-28) | Any other source, or the SEC registration date: not used. |

<a id="a3"></a>
## A3. One way in

- **A3.1** Every bot sends into the holding area `bots.research_submissions`. That includes researchers, list builders, portal-night-bot, the Activity Collector, the Enricher when it is only finding facts, and visitor requests. There is no side door. No hand fix. No one-off migration that writes a page table.
- **A3.2** `bots.research_enrichments` can store a bot’s structured result. It is still holding. It is not a publish.

<a id="a4"></a>
## A4. The holding door

- **A4.1** Only a known bot gets in, and each bot has its own key. Turning that key off stops that bot. The others keep working. Research bot submissions pass the submission check, A12.2 (Alex, 2026-10-28).
- **A4.2** A bot may send as many distinct firms in an hour as the hourly limit. That limit is one setting, `door_hour_cap`. It starts at 100. Those firms are checked now. Further firms in that hour, up to three times the limit, are kept and wait until the next hour. They are not thrown away. More than three times the limit in an hour is an attack: that bot’s key is blocked, its waiting items are frozen, and Alex gets one alert. Only Alex can turn that bot back on. Changing the hourly limit changes the attack line with it. There is no second setting.
- **A4.3** An exact copy is dropped at the door. It is not stored again.
- **A4.4** The entry check works the queue oldest first (The Checker runs this check today; automatic checks, when built, run the same check.) (Alex, 2026-10-28). A bot whose items fail more than half the time, after at least 10 checked items in a day, is paused, and Alex gets one alert.
- **A4.5** Retention of failed holding items, processed uploads and search logs: see [A11.1](#a11).

<a id="a5"></a>
## A5. The Checker

- **A5.1** The entry check is the only way an item is published. An item is shown only after it passes the entry check (A5.2). The Checker runs this check today; automatic checks, when built, run the same check. (Alex, 2026-10-28)
- **A5.2** For each item it checks three things:
  - The link is real. It is not a search or chat page, and it opens.
  - The link matches the item (this firm, this person, this fund, this case).
  - The source level, from the ranking in [A1](#a1).
- **A5.3** A register or firm-site item is published with the date and checked-by **Checker**. Those two values, and the source level, are stored on the item. They are not drawn on the page. An elsewhere-online item is held as Unconfirmed and is not shown, unless Sources per page part ([A2](#a2)) says that part may show it. A failure stays in holding with the reason; how long: see [A11.1](#a11). Nothing is re-checked unless Alex asks. The revision of social links and contact details every few months counts as that standing ask. News rows that already have a check mark stay checked. They are not re-checked in this pass.
- **A5.4** The Enricher does not publish; its fixes pass the fix check, A12.3 (Alex, 2026-10-28). The Activity Collector does not write `investments` directly; its deals and funds pass the activity check, A12.4 (Alex, 2026-10-28).

<a id="a6"></a>
## A6. Three marks on every item

- **A6.1** The entry check sets these once, on the item itself (The Checker runs this check today; automatic checks, when built, run the same check.) (Alex, 2026-10-28):
  - **checked-on**, the date (`checked_on`)
  - **checked-by**, the name Checker (`checked_by`)
  - **source level**, 1, 2, 3, or 4 (`source_level`)
- **A6.2** The columns are on the item tables: `press_item_firms`, `timeline_events`, `firm_check_rows`, `firm_people_roles`, `firm_profile_facts`, `firm_legal_items`, `reviews`, and `vc_source_facts`. They are not on `fact_sources`. A fact can have several source links, and press and the 10 checks do not keep the source pill in `fact_sources`.
- **A6.3** `firm_check_rows.searched_at` and the news `check_mark` stay. They are not dropped. For the 10 lab firms, a search date is copied into `checked_on`. A news row already marked `checked_correct` or `checked_wrong` copies `last_checked_at` into `checked_on`, and the source level from the link. That copy is saved first in `marks_fold_backup`. A row the Checker did not check keeps `checked_by` empty. The page still reads the old fields.
- **A6.4** `checked_on`, `checked_by`, and `source_level` are internal only. They are never shown on the live site, in any block. Alex rejected the Sequoia mockup that put a grey “checked &lt;date&gt;” next to the source pill. Do not build that.

<a id="a7"></a>
## A7. One home per data kind

| Rule |  Kind | The one home | What gets merged in |
|---|---|---|---|
| **A7.1** | Firm names | `firm_aliases`, with a type: display, short name, legal, fund entity, old name, or website, plus the source | Gaps in `legal_name` |
| **A7.2** | Funds | `funds` | `firm_profile_facts` where section is funds |
| **A7.3** | AUM | one fact: the SEC Form ADV figure (Item 5F regulatory assets, with the as-of year) first; if there is none (e.g. non-US firms), the AUM stated on the firm’s own website (level 2), with a link to that page; if neither exists, no AUM and the tile is hidden (Alex, 2026-10-28) | Other AUM values are not used as a fallback |
| **A7.4** | Deals and portfolio companies | `investments` and `portfolio_companies` | Timeline lines and collector rows that skip the Checker |
| **A7.5** | News | one news item per normalized URL | `press_items` and `timeline_events` |
| **A7.6** | Legal | `firm_legal_items` (this feeds checks 4, 6, and 7) | `regulatory_records` and `legal_matters` |
| **A7.7** | People | `firm_people_roles` | `people` and `fund_people` |
| **A7.8** | Reviews | `reviews` | Leftover `founder_accounts` |
| **A7.9** | LPs | `firm_profile_facts` section `lps`, confirmed only | `bots.firm_lps` (holding until a confirmed row is published) |
| **A7.10** | The 10 checks | `firm_check_rows` plus the findings in `vc_source_facts` | Stored pill text that does not match the findings |

- **A7.11** Same-item keys: fund = fund name or SEC file number; news = normalized URL (lower case, no scheme, no `www.`, no query, no hash, no trailing slash); person = name plus kind; legal = case number or file number; LP = firm plus lowercased institution name; deal = firm plus company plus round.
- **A7.12** The winner is the higher source level, then the newer date, then the more complete row. Every source is kept. The losing value is saved as a note. If two values still disagree, they go to the Checker review list. Each merged item gets one entry check. The merge log is permanent. The merge backup is kept 3 days, then deleted only with Alex’s OK.
- **A7.13** On the 10 lab firms, exact copies in a home are the only rows removed. A different value stays on the page and is listed for the Checker. `fact_events` stays the public fact counter. The log is `home_merge_log`. The backup is `home_merge_backup`, and it is not deleted without Alex’s OK. `firm_aliases.alias_type` is display, short name, legal, fund entity, old name, or website. The page does not read it.
- **A7.14** A side row that has no home is backed up, then checked once. If it passes the entry check, the row moves into its home. If it does not, the row is deleted (The Checker runs this check today; automatic checks, when built, run the same check.) (Alex, 2026-10-28). Only the key (the URL, or the id when there is no URL), the kind, the firm, and the reason stay on `rejected_items`. The Checker will not add that key again. A legal-matter link is found by the matter id stored on the held log. That backup is `home_held_backup`. It is kept 3 days and is not deleted without Alex’s OK. The old tables themselves are not dropped.

<a id="a8"></a>
## A8. Live counts

- **A8.1** On the 10 lab firms, the 10 check counts and pills are counted once and saved, in `firm_check_pills`. They are counted again, and saved, only when the Checker publishes new data to that firm (a trigger on the data the checks read marks the firm and recounts it once). If no data changed, nothing is recounted. Pages only read the saved counts. `firm_page` (pills and the checks-done number) and `my_firms` (the My firms pill) read them and never recount. Check 8 comes from the IAPD registration row, not from a hand-typed label.
- **A8.2** If the counting logic or `ingest_settings` change, the same change must rerun the backfill (`select public.refresh_firm_check_pills(id) from public.firms where public._lab_firm(id);`) for every affected firm. Finder bots never touch the counts. Only the Checker's publishing, or that backfill, changes them.
- **A8.3** Section counts and the activity tiles are still computed when the page is read. A firm that is not one of the 10 still reads the old stored pill. The old lab pill and score copied to `live_count_backup` are kept 3 days and are not deleted without Alex’s OK.
- **A8.4** Page speed is tested automatically. After each deploy, CI times the anon `firm_page` call for the 10 lab firms (`scripts/check_page_speed.mjs`, in a rolled-back call that records nothing) and fails if any firm takes more than 2000 ms.

<a id="a9"></a>
## A9. List limits and archiving (the one table)

- **A9.1** List limits (Alex, 2026-10-28). Shown on the page / max kept in the system: Every Part B block points here instead of restating these numbers. These replace the earlier soft caps. Every list archives its oldest items past its limit (kept, hidden, never deleted); the only exception is the 10 checks (A9.8) (Alex, 2026-10-28).

| Rule | List | Shown on the page | Max kept | Past the max |
|---|---|---|---|---|
| **A9.2** | People | 10 shown + Show all | 20 | New items still come in and the oldest are archived (kept, hidden), never deleted. |
| **A9.3** | News | Latest 10 + Show all (“The latest 10 news items, plus Show all for the rest that are still on the page.”) | 50 | When a new item comes in past 50, the oldest is archived (kept in the database, hidden), never deleted. |
| **A9.4** | Founder reviews | 1 latest + Show all (“One latest founder review, plus Show all.”) | 50 | Oldest archived (kept, hidden), never deleted; tell Alex when a firm passes 50 (Alex, 2026-10-28). |
| **A9.5** | Deals | 1 latest + Show all (“One latest deal, plus Show all.”) | 1,000 | 1 for now, may increase later (Alex, 2026-10-28). New items still come in and the oldest are archived (kept, hidden), never deleted. |
| **A9.6** | Funds | Latest fund tile + "N funds on SEC record · Show all" (“One latest fund tile, plus the line “N funds on SEC record · Show all”.”) | 100 | New items still come in and the oldest are archived (kept, hidden), never deleted. |
| **A9.7** | LPs | Only confirmed LPs are shown (see B9) | 100 (“LPs stay at 100.”) | Every list archives the oldest past its max. |
| **A9.8** | The 10 checks | Per Part C | No cap | Never archived. Checks will be run fresh on demand when a user presses or pays; details come in the later checks review (Alex, 2026-10-28). |
| **A9.20** | Legal items (cases and regulator actions) | 10 shown + Show all (A2.4) | 100 per firm | Past 100, the oldest go to the archive (stored, hidden), never deleted (Alex, 2026-10-28). |
| **A9.15** | Interviews (per current person) | Up to 10, most viewed first (A2.3); not shown until the design is approved (B10.8) | 10 | The rest are stored, not shown. (Alex, 2026-10-28) |
| **A9.16** | Search suggestions | Up to 8 firms (B2.1) | — | — (Alex, 2026-10-28) |
| **A9.17** | Sector pills | Top 5 sectors + a grey "Other N" pill, only when the firm has 10 or more deals (B6e.9) | — | — (Alex, 2026-10-28) |
| **A9.18** | SEC fact pills | At most 7 (B4.1) | — | — (Alex, 2026-10-28) |
| **A9.19** | Thesis | Max 1,000 characters (B7.3) | 1,000 characters | — (Alex, 2026-10-28) |
- **A9.12** One alert per firm when a cap is hit.
- **A9.14** These caps are not a license to delete. The archive file is the copy, and the row can be shown again from Show all. For the 10 lab firms the copy is `data/lab-cap-archive/index.json` plus `lab_cap_archive`. A row past the cap is marked archived and stays in the database. Every count that covers all deals still includes archived rows, so a firm over the deal cap does not drop its shown total. That covers Deals, last 12 mo, the latest-deal tile, the Show all total, and the sector pills, which count all deals ([B6e.9.6](#b6e)) (Alex, 2026-10-28). My firms shows check pills, not a deal total. `lab_cap_alerts` holds one row per firm. `lab_soft_caps` is not run until Alex says to apply it.

<a id="a10"></a>
## A10. Search and new firms

- **A10.1** Search matches the firm name, the short name, and the website. Those names live on `firm_aliases` with a type. `firm_suggest` already reads aliases. There is no second search table.
- **A10.2** On the 10 lab firms, `firm_suggest` matches the firm name, the short name, the slug, and aliases whose type is display, short name, or website. It does not match a legal name or a fund entity name. Those rows stay in `firm_aliases`. Check 1 and check 6 still read them, each on its own search. A commonly used short name is stored as type short name, source firm site. A legal name is still copied when the firm has an SEC CRD and a legal name. A fund name is still copied when that fund is real and a source link is on sec.gov or on the firm’s own domain. The firm’s domain is the website alias. A news link is not copied. A label that is not a name, such as Funds or Regulatory AUM, is not copied.
- **A10.3** A new firm is deduped by registry id first (SEC CRD, FCA, Companies House, another national regulator, or a GLEIF LEI). If there is no registry id, match on domain plus name plus HQ, and mark the firm **no registry ID**.

<a id="a11"></a>
## A11. How long rows are kept

- **A11.1** Search logs and uploads that have been processed are kept 30 days. Failed holding items are kept 7 days. The merge log is kept. Legal items and the 10 checks are not deleted by a retention job.

<a id="a12"></a>
## A12. Shared checks list

- **A12.1** A new firm passes the new-firm check (it is a real VC, growth, PE or hedge fund firm with a working website, and it is not already in the queue) before it is added to the queue. List Builders (all regions) runs this check today; automatic checks, when built, run the same check. (Alex, 2026-10-28)
- **A12.2** A research bot's item passes the submission check (it has a source link, a source level (A1) and the three marks (A6), and it goes through the holding door (A4)). Researchers 1–3 runs this check today; automatic checks, when built, run the same check. (Alex, 2026-10-28)
- **A12.3** A fix passes the fix check (the new source is at the same level or higher (A1), and the old value is archived, never deleted) before it replaces a value. The Enricher runs this check today; automatic checks, when built, run the same check. (Alex, 2026-10-28)
- **A12.4** A deal or fund passes the activity check (it has a source link; the amount and lead are shown only when that source states them) before it is shown. The Activity Collector runs this check today; automatic checks, when built, run the same check. (Alex, 2026-10-28)
- **A12.5** An item shown on the live page passes the page check (it follows its rulebook rule: source link present, limits from A9, hidden items stay hidden). The Tester runs this check today; automatic checks, when built, run the same check. (Alex, 2026-10-28)

<a id="b"></a>
# B. The page

Items .1 to .6 in each block follow the 2026-10-27 snapshot layout: 1 what is drawn, 2 where it is read from, 3 who collects it, 4 checks on the data, 5 when it is shown or hidden, 6 known problems (RULES_AUDIT). Where a snapshot item disagrees with Part A, Part A wins (P.4).

<a id="b1"></a>
## B1. Site logo and wordmark

- **B1.1** The Regretamin lockup in the corner. It is not the firm’s logo.
- **B1.2** A static file. No table.
- **B1.3** Designed asset. No bot.
- **B1.4** No data rule.
- **B1.5** Always shown.
- **B1.6** No problem found (RULES_AUDIT 5).

<a id="b2"></a>
## B2. Search box and suggestions

- **B2.1** The box on the home page, the firm page, and the empty state. After a short pause it lists up to 8 firms. Choosing one opens `/vc/<slug>/`. No match offers “Request this firm.” Limit: [A9.16](#a9) (Alex, 2026-10-28).
- **B2.2** What `firm_suggest` reads and matches: see [A10](#a10). It returns slug, display name, short name, and HQ. `launch/js/search.js` calls it. The list looks the same.
- **B2.3** Names arrive when a firm is created from the queue or merged (`docs/DEDUPE.md`, `docs/FIRM_REQUESTS.md`). List builders and visitor requests fill the queue. The enricher creates the page.
- **B2.4** Only published, non-test, real, not-deleted firms. Match is a substring. A prefix ranks first.
- **B2.5** A deleted or unpublished firm is absent.
- **B2.6** Lab display names match `firms.name` (RULES_AUDIT 1). Sequoia has no legal name to alias (RULES_AUDIT 2).
- **B2.7** Search matching and new-firm rules: see [A10](#a10).

<a id="b3"></a>
## B3. Firm header

- **B3.1** The large name, then a meta line: HQ, short name, and the website.
- **B3.2** `firm_page` builds `firm.name` from `coalesce(display_name, name)`, `firm.sec_name` from `coalesce(legal_name, name)`, `firm.short_name`, `firm.hq` from `firm_hq_format`, `firm.website` from the primary domain, `firm.assets` from `_firm_assets`. The meta line in `company.js` `metaLine` prints HQ, short name, and the website. It does not print the legal name.
- **B3.3** HQ and the website start on the queue row (list builder or request). Display name is cleaned by `firm_display_name` when the page is created.
- **B3.4** No written rule that HQ must be a city from IAPD. The queue stores `hq_city`, `state`, and `country`.
- **B3.5** The header shows whenever the page loads. Hero cards (staff, founded, AUM as cards) were removed and are not drawn.
- **B3.6** Legal name gaps: RULES_AUDIT 2. Slug: no problem (RULES_AUDIT 4).
- **B3.7** Sources for HQ, website and founded year: [A2.13–A2.15](#a2) (Alex, 2026-10-28).

<a id="b4"></a>
## B4. SEC fact pills

- **B4.1** Small links under the header for hero facts whose source is sec.gov. Rules (one rule (Alex, 2026-10-28)): at most 7 pills. HQ is never a pill. A fund (for example a newly raised fund) is never a pill. No two pills say the same thing, and no pill for any info already shown elsewhere on the page (e.g. no AUM pill when the B6d AUM tile shows it). AUM and “fund gross assets” are labelled differently. Pills are flagged for a full review later; more may be dropped. Limit: [A9.18](#a9).
- **B4.2** `firm_page` hero list: `firm_profile_facts` where `hero_label` is set and a `fact_sources` row exists. `company.js` `secPills` keeps only a sec.gov source.
- **B4.3** The enricher, from a Form ADV on sec.gov / adviserinfo.sec.gov. Item 5F is the assets figure the helper looks for.
- **B4.4** The fact needs a source or it is not in the hero list. The pill needs the host to be sec.gov.
- **B4.5** Hidden when the hero list is empty or no source is sec.gov.
- **B4.6** The assets helper can drop the unit (RULES_AUDIT 11).

<a id="b5"></a>
## B5. Score bar

- **B5.1** The visitor does not see a score. There is no score block in `company.js`.
- **B5.2** `score_results` (current row), `score_inputs`, and `score_result_parts` still exist. `vc_scores` still exists. Neither is read by `firm_page`.
- **B5.3** Unknown for the stored rows. The formula in `score/` is a copy of the old site and is not run on publish. No bot recomputes it.
- **B5.4** The written formula is `docs/toxy-score-v2-rules.md`. It is not enforced on the live page.
- **B5.5** Nothing shows it. Nothing hides it. It is not in the layout.
- **B5.6** RULES_AUDIT 21.

<a id="b6"></a>
## B6. Activity strip

- **B6.1** The strip sits above the sections. It is omitted when there is no tile, no deal, and no review.

<a id="b6a"></a>
### B6a. “Active” tile

- **B6a.1** A tile when the firm has a deal or a fund close in the last 365 days.
- **B6a.2** `investments.invested_on` and `funds.closed_on`, both `data_status = real`. `_firm_activity`.
- **B6a.3** Moved to [R5](#r5) (old note).
- **B6a.4** The 365-day window is display math, not a collect rule.
- **B6a.5** The tile is absent when both counts are zero.
- **B6a.6** RULES_AUDIT 12.

<a id="b6b"></a>
### B6b. Deals in the last 12 months

- **B6b.1** A count.
- **B6b.2** `investments` where `invested_on` is within 365 days and `data_status = real`.
- **B6b.3** Same as B6a.3, now an old note in [R5](#r5).
- **B6b.4** No required fields beyond the row existing. Amount can be empty.
- **B6b.5** The tile is omitted when the count is 0.
- **B6b.6** RULES_AUDIT 12.

<a id="b6c"></a>
### B6c. Latest fund tile

- **B6c.1** The newest fund that has a raised amount, with the name, the amount, and a source link: the filing, or the news or trusted page the amount came from (see B6c.8) (Alex, 2026-10-28).
- **B6c.2** First choice: `funds.raised_usd` or `funds.size_usd`, `funds.name`, `funds.closed_on`, `funds.filing_url` (the source link: the filing, or the news or trusted page the amount came from; see B6c.8 (Alex, 2026-10-28)). On the 10 lab firms, if that amount is missing, `earlierFund` reads a Funds section line shaped “Name · $amount · date.” If that is also missing, the assets tile is used.
- **B6c.3** Profile-fact fund lines: the enricher, from Form D or Form ADV.
- **B6c.4** The tile skips a $0 amount. It skips lines that look like AUM or gross assets.
- **B6c.5** Other firms, outside the 10, still show a fund with no amount.
- **B6c.6** RULES_AUDIT 10.
- **B6c.7** Latest fund tile rule (Alex, Oct 27 2026 design note): A latest fund with an amount stays. A $0 or missing amount uses the most recent earlier fund that raised money (name, amount, date, filing link). If none did, the tile is AUM from the SEC/ADV figure already on the page. Neither shows nothing.
- **B6c.8** Rule (Alex, 2026-10-28): amount source: see [A1.8](#a1). The tile link is the sec.gov filing when the source is sec.gov. When the amount or date comes from an approved news outlet or trusted site, that page is the link instead.
- **B6c.9** Shown count, max kept, and archiving for funds: see [A9.6](#a9). Amount source: [A1.8](#a1).

<a id="b6d"></a>
### B6d. Assets under management tile

- **B6d.1** Shown on the 10 lab firms only when there is no fund amount at all, including no earlier fund that raised money (see the latest fund tile rule in [B6c.7](#b6c)). Label “AUM” (Alex, 2026-10-28).
- **B6d.2** AUM source order per [A7.3](#a7) (Alex, 2026-10-28): the SEC Form ADV figure first (hero fact whose label maps to Regulatory AUM, or a profile fact that cites Item 5F or “regulatory AUM”; Schedule D gross assets are skipped). If there is none (e.g. non-US firms), the AUM stated on the firm’s own website (level 2), with a link to that page. If neither exists, the tile is hidden.
- **B6d.3** SEC Form ADV Item 5F, via the enricher.
- **B6d.4** A new AUM fact must contain a digit. The helper does not keep a trailing B, M, or K.
- **B6d.5** Hidden when neither a Form ADV figure nor a firm-website AUM exists (B6d.2) (Alex, 2026-10-28).
- **B6d.6** RULES_AUDIT 11.

<a id="b6e"></a>
### B6e. Latest deal, and “Show all”

- **B6e.1** Company, round, date, and source host. “Show all” opens the rest.
- **B6e.2** `investments` joined to `portfolio_companies.name`. Source is the first http(s) URL in `investments.source_urls`. `firm_activity_list` loads the full list.
- **B6e.3** Lab timeline regex, the Sequoia copy, or the activity collector. Press and Form D are not wired as a general deal writer.
- **B6e.4** `data_status = real`. No check that the round is a short name. Sorted by date.
- **B6e.5** The block is omitted when there is no deal. The full list waits until the page is open.
- **B6e.6** RULES_AUDIT 12 and 13.
- **B6e.7** Shown count, max kept, and archiving for deals: see [A9.5](#a9).
- **B6e.8** A deal row has a sector column, and a column that reads round · amount · Lead. Those three are filled only when a source states them. An empty amount stays empty.
- **B6e.9** Latest investments block (Alex, 2026-10-28). Its rules, one per line:
  - **B6e.9.1** Shown count: per [A9.5](#a9).
  - **B6e.9.2** A deal with no stated sector leaves the sector cell blank, never "No data yet".
  - **B6e.9.3** The sector summary sits inside this block: pills with deal counts for the top 5 sectors (largest first), a grey "Other N" pill for the rest, and "Show all" opening the deals pop-up. Sector pill limit: [A9.17](#a9).
  - **B6e.9.4** Counts only, no percentages.
  - **B6e.9.5** Deals with no sector are not counted and get no pill.
  - **B6e.9.6** The pills count all of the firm's deals, not only the last 12 months.
  - **B6e.9.7** The summary shows only when the firm has 10 or more deals in total; with fewer, it is hidden on the page and in the pop-up. The same rules apply to the pop-up header.
  - **B6e.9.8** "Deals, last 12 mo" is a separate number on the page: just the count of deals in the last 12 months.
  - **B6e.9.9** A sector name is at most 2 words and 25 characters (Alex, 2026-10-28). Longer names are mapped to a short standard name.
- **B6e.10** Sector pills: no data that has passed its check means the block is hidden from users (no empty box, no "No data" text). It appears by itself once data passes. (Alex, 2026-10-28)

<a id="b7"></a>
## B7. Thesis (replaces Overview; Alex, 2026-10-28)

- **B7.1** New block “Thesis”. It replaces the Overview block, which is removed from the page. Same design as the old Overview block ([R4](#r4)).
- **B7.2** Holds the firm's investment thesis (what they invest in and why), copied word for word from the firm's own website. No other source: not news, LinkedIn, SEC or any other site. Source level 2. The link to that website page is always kept and shown.
- **B7.3** Max 1,000 characters. Not rewritten by us. Limit: [A9.19](#a9) (Alex, 2026-10-28).
- **B7.4** No thesis on the firm's website: the block is not shown.
- **B7.5** Door check: the link opens and is on the firm's own domain; the text is found on that page; length 1,000 characters or less.
- **B7.6** Old Overview rows are hidden, not deleted. Nothing is moved from them into the header or fact pills. A fact that the header or fact pills already show from their own sources keeps showing there; an Overview-only fact is simply no longer shown. Backup first; nothing is deleted without Alex's "Yes, delete".
- **B7.7** Needs a mockup on the Sequoia lab page before building.

<a id="b8"></a>
## B8. Firm & funds

- **B8.1** One row per stored fund fact: name, amount, date, source pills.
- **B8.2** `funds` table only (A7.2 wins) (Alex, 2026-10-28).
- **B8.3** Enricher, from EDGAR Form D and Form ADV Schedule D.
- **B8.4** Name required. Amount, when present, is a number. Dedupe is the fund name or the fund key.
- **B8.5** Hidden rows and rows with no source are omitted.
- **B8.6** RULES_AUDIT 10.
- **B8.7** Shown count, max kept, and archiving: see the list limits table in [A9](#a9). Sources: [A2.12](#a2) (Alex, 2026-10-28).
- **B8.8** Funds: no data that has passed its check means the block is hidden from users (no empty box, no "No data" text). It appears by itself once data passes. (Alex, 2026-10-28)

<a id="b9"></a>
## B9. Limited partners

- **B9.1** One line per confirmed LP: "name · $total (N funds)", the count only when 2 or more (A2.2) (Alex, 2026-10-28). No LPs: the block is omitted.
- **B9.2** `firm_profile_facts` `section = lps`. Label is the institution. The page shows only name and total amount (A2.2); type, year and status are not shown, and status is kept in the system only (Alex, 2026-10-28). `bots.firm_lps` is not read.
- **B9.3** Profile rows: the enricher, from public filings and LP reports (the gold example says so; the exact site is whatever URL was sent). Bot rows: a researcher dump, often pensions and Form D related parties.
- **B9.4** Profile: name required, type optional, source required. Bot table: name, status confirmed or lead, URL, type from a fixed list, cap 100, unique on name plus fund.
- **B9.5** A lead (an LP named only by a weaker source, held as Unconfirmed) is not shown. No source, or hidden, drops the row. (Alex, 2026-10-28)
- **B9.6** RULES_AUDIT 22.
- **B9.8** Shown count, max kept, and archiving: see the list limits table in [A9](#a9). LP sources: [A2](#a2).

<a id="b10"></a>
## B10. People and board seats

- **B10.1** Rule (Alex, 2026-10-28): only current people are shown, grouped into board and officers. The moves group is not shown. A person who left is taken off the page and archived (kept, hidden) for possible later use. News about them can still show like any news.
- **B10.2** `firm_people_roles`: `person_name`, `role`, `kind`, not hidden, with a source. The older `people` and `fund_people` tables are not this section.
- **B10.3** Enricher, typically Form ADV Schedule A (officers) and board seats from filings or the firm site. The gold example uses the IAPD PDF.
- **B10.4** One person per name. Same person and kind with the same role adds the source. A different officer role is a conflict. The note guard hides Schedule A blobs.
- **B10.5** Hidden rows are omitted. The browser also refuses note-like text.
- **B10.6** RULES_AUDIT 9.
- **B10.7** On the lab firms, once this is built: people shown plus Show all. Shown count, max kept, and archiving: see the list limits table in [A9](#a9). People sources: [A2](#a2).
- **B10.8** Interviews are stored up to 10 per person (link + headline, most viewed first, see [A2.3](#a2) and [A9.15](#a9)). Where they appear (on the page or on a tap on a person) is decided with the design, mockup first; they are not shown until it is approved. (Alex, 2026-10-28)
- **B10.9** People: no data that has passed its check means the block is hidden from users (no empty box, no "No data" text). It appears by itself once data passes. (Alex, 2026-10-28)

<a id="b11"></a>
## B11. Legal and regulatory section

- **B11.1** Sources and display per [A2.4](#a2) (the source list lives only there (Alex, 2026-10-28)): 10 legal items (cases and regulator actions), active first, then the rest by most recent, plus Show all. Each row has a title, a year, a status, and source pills. Context rows are not their own rows: a mention about an existing case is an extra link on that case; one with no matching case is not shown and stays a lead for the check (Alex, 2026-10-28).
- **B11.2** `firm_legal_items`, not hidden, with a source. Group, title, year, status, note. This is separate from the 10-check details.
- **B11.3** Allowed sources: see [A2.4](#a2). Court hosts and Justia, Law360, Casetext become `case`. sec.gov, FINRA, and the FCA become `regulator`. Anything else becomes `context`, which is never its own row (B11.1) (Alex, 2026-10-28).
- **B11.4** Title required. An allegation is held. Lab allegations need a court or regulator URL.
- **B11.5** Hidden or unsourced rows are omitted. “Lead” in the title is not a hide rule.
- **B11.6** RULES_AUDIT 7 and 8.
- **B11.7** Legal items: up to 100 kept per firm; past 100 the oldest are archived (stored, hidden): see [A9.20](#a9) (Alex, 2026-10-28). Case display rules: [A2](#a2).

<a id="b12"></a>
## B12. News

- **B12.1** One list, newest first, since 2023. A card has a headline, a date, outlet pills, and a tag such as Court or Fund when the timeline item had one. The browser may merge some of those into fewer cards. That merge is not stored.
- **B12.2** Press: `press_items` plus `press_item_firms` where `check_mark = checked_correct` and the URL is non-empty. Timeline: `timeline_events` where `check_mark = checked_correct`, not hidden, and a source URL or a `fact_sources` link exists. `company.js` `buildNews` unions them.
- **B12.3** Enricher. Press is an outlet story (TechCrunch, Bloomberg, Reuters are real lab examples; the firm’s own posts are never shown in News (Alex, 2026-10-28)). Timeline is an event (a filing, a raise, a court date). The bot chooses which section. There is no classifier.
- **B12.4** Press needs outlet, headline, and URL. Timeline needs a date and an event. Publish dedupes press by the exact URL and timeline by date plus text. It does not compare the two tables. Display normalizes the link and groups headlines that share an event word and a name within 7 days.
- **B12.5** `checked_wrong` and `not_checked` stay stored and are not drawn. Dates before 2023 are not drawn. The firm’s own site posts and blog are not shown; there is no “Own media” label (Alex, 2026-10-28).
- **B12.6** News is shown only after it passes the news check (the link opens, the story names the firm, the outlet is an outside source from the A2.6 list). The Checker runs this check today; automatic checks, when built, run the same check. (Alex, 2026-10-28). RULES_AUDIT 14.
- **B12.7** On the lab firms, once this is built: the latest news items, plus Show all for the rest that are still on the page. Shown count, max kept, and archiving: see the list limits table in [A9](#a9).
- **B12.8** News: no data that has passed its check means the block is hidden from users (no empty box, no "No data" text). It appears by itself once data passes. (Alex, 2026-10-28)

<a id="b13"></a>
## B13. What founders say, and the review cards

- **B13.1** The reviews block reads the `reviews` table only (Alex, 2026-10-28). The activity strip shows the latest public founder review, and “Show all” lists the rest.
- **B13.2** The strip reads `reviews`: author, role, company, round, body, date, ratings, source URL, type. Filter: founder, public, approved. Moved `founder_accounts` rows are excluded from the old section.
- **B13.3** Enricher “What founders say” items are written to `reviews`. Gold examples use LinkedIn and similar posts. A visitor form can also insert a review, which starts pending. The activity collector is not documented as a review writer.
- **B13.4** One person in `who`, a quote, a source. Same URL or same quote text merges. Own-site quotes are not called independent.
- **B13.5** A founder quote is shown only after it passes the founder review check (the link opens, it names the firm, it is quoted word for word, the writer is a founder). The Checker runs this check today; automatic checks, when built, run the same check. (Alex, 2026-10-28). Pending, non-public, or non-founder rows are not drawn.
- **B13.6** RULES_AUDIT 19.
- **B13.7** On the lab firms, once this is built: one latest founder review, plus Show all. Shown count, max kept, and archiving: see the list limits table in [A9](#a9).
- **B13.8** Founder reviews: no data that has passed its check means the block is hidden from users (no empty box, no "No data" text). It appears by itself once data passes. (Alex, 2026-10-28)

<a id="b14"></a>
## B14. Source pills

- **B14.1** The grey links under a row: label, date, and the URL. News cards also list outlets.
- **B14.2** `fact_sources` joined to `sources`, via `_src`. Press uses the article URL itself. Timeline uses `source_url` when it is set, otherwise `fact_sources`.
- **B14.3** Whatever URL the bot sent, if it passed the source filter. Trusted hosts are the allowlist in `trusted_source_domains` plus government and court hosts (`docs/SOURCE_TIERS.md`).
- **B14.4** Search and chat URLs are refused at ingest. A fact with no usable source is flagged `needs_source` and hidden.
- **B14.5** A section row with an empty source list is not returned, except press and the check pills.
- **B14.6** RULES_AUDIT 17 (no unsourced lab profile facts) and 18 (the pill does not say trusted or other).

<a id="b15"></a>
## B15. Home page

- **B15.1** The headline, the search box, and the marketing text. It does not list firms or scores.
- **B15.2** `launch/copy.json` and `launch/build.py`. No firm table on that screen.
- **B15.3** No bot.
- **B15.4** No data rule.
- **B15.5** Always the same shell. Firm data appears only after a search.
- **B15.6** No problem found for a missing firm grid, because the current home page is not a directory. Older docs that describe a scored homepage are old (RULES_AUDIT O5).

<a id="b16"></a>
## B16. Account, credits, and My firms

- **B16.1** Account shows the plan, credits left, and renewal. My firms lists saved and checked firms with HQ and pill counts. It does not show a score or a legal name.
- **B16.2** `my_account` reads `check_balances` (plan, free left, paid left, period end). `my_firms` reads `watchlist`, `check_events`, `firms.name`, `firms.short_name`, `firms.hq`, and counts from `firm_check_rows`.
- **B16.3** Credits come from signup, Stripe, and the yearly refill cron. Saved firms are the visitor’s watchlist. Checked firms are spend events.
- **B16.4** The yearly refill runs hourly. Lapsed plans are downgraded hourly. The on-demand tick refunds a paid check that is not done in 24 hours.
- **B16.5** These pages require a signed-in session. Firm facts are not repeated here.
- **B16.6** `my_firms` uses `firms.name`, which matches `display_name` on all 10 lab firms (RULES_AUDIT 1 and C12b). The on-demand doc still describes a locked page (RULES_AUDIT K5).

<a id="b17"></a>
## B17. Paywall and “email me”

- **B17.1** With the lock off, the firm page opens, including News, legal, and the checks. The “email me when it’s ready” box is for a firm that still needs research, and only while signed out.
- **B17.2** `app_settings.lock_enabled`. The box writes `research_requests` / `ondemand_jobs` through `unlock_firm` and `notify_when_checked`.
- **B17.3** No bot writes the switch. Researcher 3 claims the paid lane.
- **B17.4** A finished firm does not re-enter the paid lane. Rate limits live on visitor requests (`docs/FIRM_REQUESTS.md`).
- **B17.5** The switch hides the lock. It does not hide bad rows.
- **B17.6** RULES_AUDIT A31 and K5. `docs/ON_DEMAND.md` still tells the visitor they must spend a credit.

<a id="b18"></a>
## B18. Elements that are easy to look for and are not on the page

- **B18.1** A firm logo. Not stored for the header.
- **B18.2** A score bar. Stored for some firms, not drawn.
- **B18.3** OFAC SDN named on the sanctions row. Not in the copy.
- **B18.4** OpenCorporates. Not in the source rules.
- **B18.5** `bots.firm_lps` and `regulatory_records` and `legal_matters`. Present in the database, not what these sections read.

<a id="c"></a>
# C. The 10 checks

<a id="c0"></a>
## C0. How the checks work

- **C0.1** There are exactly 10 checks. They are never merged with each other, and their searches are never merged.

| # | Check | What it is |
|---|---|---|
| [C1](#c1) | Sanctions | Lists of people and companies you cannot do business with |
| [C2](#c2) | Terrorism financing lists | Lists tied to funding terrorism |
| [C3](#c3) | Export and investment restrictions | Trade and investment bans |
| [C4](#c4) | Financial regulator actions | Fines, bans, and charges |
| [C5](#c5) | Money laundering penalties | Anti-money-laundering enforcement |
| [C6](#c6) | US court records | Federal and state cases |
| [C7](#c7) | Court records worldwide | Cases outside the United States |
| [C8](#c8) | Registration check | Investment-adviser registration, from the register |
| [C9](#c9) | People behind the fund | Partners and owners, each checked against the lists in C1, C2, C3 and C10 |
| [C10](#c10) | Political ties | Government or political roles |

- **C0.2** OpenSanctions is only one source, and only inside checks 1, 2, and 10. It is not a source for the other checks, and it does not replace a register those checks have of their own. Checks 3, 4, 5, 6, 7, 8, and 9 keep their own searches. A same-name hit that is not the same person is not a finding.
- **C0.3** On the 10 lab firms, check 1 and check 6 each search the legal name and each fund entity name. Each check calls `lab_check_search_names` with its own number. They do not share one search. The website is not one of those queries.

The checks table on the page (snapshot 2026-10-27):
- **C0.4** A table: number, title, pill, what was found, date searched. A row opens the findings. Pills are Clear, Review, Worth knowing, or Not checked yet. For check 8 the states are in C8.5 (Alex, 2026-10-28). A stored `red` is drawn as Review. While a bot holds the claim, the first unfinished row says “Checking” and the rest say “Waiting.”
- **C0.5** `firm_check_rows`: `n`, `title`, `descr`, `state`, `count_label`, `searched_at`. Findings on an open page are `firm_page` `checks[].items`, backed by `firm_details` (`vc_source_facts`) and, when those are missing, the check’s itemized findings. Name-only hits are `checks[].name_only`.
- **C0.6** Titles were inserted when the firm was created, or by the hand migration `20261023230000_sync_checks_all_launch_firms.sql`. Evidence, when it exists, came from researcher dumps into `vc_source_facts` (SEC, courts, sanctions lists). New dumps no longer copy onto this table.
- **C0.7** A new firm’s pills are `nc`. `launch/checks.py` can derive a pill and is not what the page runs. Name-only text is excluded inside `firm_details`.
- **C0.8** The table shows on the summary view. “Not checked yet” has no “nothing found” line. The date shows only when `searched_at` is set.
- **C0.9** RULES_AUDIT 20 and 16.
- **C0.10** Parked for the checks review, not changed now (Alex, 2026-10-28): A8.1 (lab pills recounted on publish) vs the C1.5–C10.5 "stored pill" lines, and C7.1 (a non-party mention can be the count).

<a id="c1"></a>
## C1. Sanctions

- **C1.1** “Government lists of people and companies you can’t do business with.” The muted line says “Searched government sanctions lists.” It does not name OFAC SDN.
- **C1.2** Pill: `firm_check_rows` n=1. A screening row, if any, is `sanctions_checks` or a `vc_source_facts` row whose field is `sanctions`. The page does not join those itself; it shows whatever was stored on the pill and in `firm_details`.
- **C1.3** Intended sources, from `docs/SOURCE_TIERS.md`: OFAC, `sanctionssearch.ofac.treas.gov`, treasury.gov, the UK sanctions list, `sanctionsmap.eu`, the UN list. The enricher is told not to file a same-name hit as a legal item.
- **C1.4** A same-name hit stays Clear and adds the muted sentence from `copy.json` `name_only`. There is no required list name.
- **C1.5** The pill shows the stored state. Nobody rechecks it when `sanctions_checks` is empty.
- **C1.6** RULES_AUDIT 6.

<a id="c2"></a>
## C2. Terrorism financing lists

- **C2.1** “Lists of people and groups linked to funding terrorism.”
- **C2.2** `firm_check_rows` n=2. Detail, when present, is a `vc_source_facts` field `terrorism_lists`.
- **C2.3** No written list of sites beyond “government lists.”
- **C2.4** No required fields beyond the pill row.
- **C2.5** Same as [C1.5](#c1).
- **C2.6** Same gap as RULES_AUDIT 20: the pill is not recomputed.

<a id="c3"></a>
## C3. Export and investment restrictions

- **C3.1** Trade and investment bans. The enricher doc uses ITAR / the DTC debarred list as the example for a name-only hit on this check.
- **C3.2** `firm_check_rows` n=3. Detail field `export_restrictions`.
- **C3.3** `trade.gov` is the example in `docs/ENRICHER.md`. No written rule that it must be that site.
- **C3.4** Name-only hits stay Clear.
- **C3.5** Same as [C1.5](#c1).
- **C3.6** RULES_AUDIT 20.

<a id="c4"></a>
## C4. Financial regulator actions

- **C4.1** “Fines, bans and charges from financial regulators.”
- **C4.2** Pill: `firm_check_rows` n=4. Detail: `vc_source_facts` regulatory actions, and `firm_legal_items` whose group is `regulator` (sec.gov, FINRA, fca.org.uk). `regulatory_records` is a third table the section does not read.
- **C4.3** SEC, FINRA, FCA, and DOJ mentions inside legal facts. Enricher for new legal items. Older facts from researcher dumps.
- **C4.4** A new allegation needs a court or regulator document on the 10 lab firms or it is rejected.
- **C4.5** The pill is the stored state, not a count of regulator rows.
- **C4.6** RULES_AUDIT 8.

<a id="c5"></a>
## C5. Money laundering penalties

- **C5.1** Anti-money-laundering fines.
- **C5.2** `firm_check_rows` n=5. Detail field `aml_penalties` or `adv_disclosures`.
- **C5.3** Unknown site list. No written rule.
- **C5.4** No extra validation.
- **C5.5** Stored pill.
- **C5.6** RULES_AUDIT 20.

<a id="c6"></a>
## C6. US court records

- **C6.1** Federal and state cases. Active cases sort first in the detail.
- **C6.2** Pill: `firm_check_rows` n=6. Detail: `vc_source_facts` legal matters for the firm, and `firm_legal_items` group `case`. Status words (active, terminated, settled) are read in `company.js` `caseStatus`.
- **C6.3** Allowed sources: the list in [A2.4](#a2); a link is required (Alex, 2026-10-28). The case group is set when the source host is one of those.
- **C6.4** Leads are held. The legal key dedupes on a case number and misses a “Lead” prefix.
- **C6.5** Rule (Alex, 2026-10-28): a count with no itemized rows shows nothing on the page, and no CourtListener search link is shown (a search page is not a source). The count or news story stays as a lead for the check (Alex, 2026-10-28). Cases show only once each has its own court or regulator link. News about a lawsuit can still show in News with its article link.
- **C6.6** RULES_AUDIT 7.

<a id="c7"></a>
## C7. Court records worldwide

- **C7.1** Cases outside the U.S. A non-party mention can be the count.
- **C7.2** `firm_check_rows` n=7. Detail field `courts_worldwide`, plus legal facts whose text looks non-US.
- **C7.3** No written court list.
- **C7.4** No extra validation.
- **C7.5** Stored pill.
- **C7.6** RULES_AUDIT 20.

<a id="c8"></a>
## C8. Registration check

- **C8.1** “Registered with the regulator as an investment adviser, and active.”
- **C8.2** Source: only the firm's own IAPD page on sec.gov (level 1, the register). The Overview is gone (replaced by Thesis, [B7](#b7)), so nothing here comes from it.
- **C8.3** Stored on the check 8 row in `firm_check_rows` (n=8), set only after it passes the registration check (C8.4); The Checker runs this check today; automatic checks, when built, run the same check. (Alex, 2026-10-28): registered or exempt reporting, since year, active or not, SEC/CRD number, and the IAPD link.
- **C8.4** Door check: the link must be an adviserinfo.sec.gov page for that firm, and the status must be one of the fixed list (Registered, Exempt reporting, Not active).
- **C8.5** Check 8 only (Alex, 2026-10-28): a US firm found on IAPD is Clear (registration line + link); a US firm not found is "Not on the list"; a non-US firm (from HQ country) gets a grey pill with the note "SEC register doesn't apply: firm is based outside the US", not counted for or against.
- **C8.6** RULES_AUDIT 8 and 20.

<a id="c9"></a>
## C9. People behind the fund

- **C9.1** Partners and owners, each checked against the lists in [C1](#c1), [C2](#c2), [C3](#c3) and [C10](#c10).
- **C9.2** `firm_check_rows` n=9. Detail field `people_screen`, or a legal fact whose entity starts with `partner:`.
- **C9.3** The people themselves are Form ADV Schedule A, via the enricher, into `firm_people_roles`. The screening of those people is a different store.
- **C9.4** A person publish checks the name. It does not set this pill.
- **C9.5** Stored pill.
- **C9.6** RULES_AUDIT 9 and 20.

<a id="c10"></a>
## C10. Political ties

- **C10.1** People at the firm who held government or political roles. Worth knowing when a hit is a partner.
- **C10.2** `firm_check_rows` n=10. Detail field `pep`.
- **C10.3** No written registry.
- **C10.4** A surname-only line is not a name-only flag (`docs/ENRICHER.md`).
- **C10.5** Stored pill.
- **C10.6** RULES_AUDIT 20.

<a id="r"></a>
# R. Removed (kept for history)

Nothing in this part is a rule.

<a id="r1"></a>
## R1. What the live code still does

- **R1.1** These are conflicts with this guide. They are not permissions.
- **R1.2** `toxy-enricher` still publishes at ingest for a firm that is not one of the 10 lab firms. On those 10, enrich lands in holding and the Checker publishes.
- **R1.3** The Activity Collector wrote Y Combinator investments straight into `investments`.
- **R1.4** One-off migrations wrote Sequoia’s `$82.2B`, Sequoia’s 10 deals, and the news check marks.
- **R1.5** Press and timeline are still two tables. The page merges some of them only in the browser.
- **R1.6** `bots.firm_lps` and `firm_profile_facts` both hold LP names. Confirmed LPs on the profile table are the page home.
- **R1.7** Pills and some counts are stored. This guide says they are computed.
- **R1.8** The ingest reply still names `docs/DATA_RULES.md`. That string is code, not a rule.
- **R1.9** `docs/data-model.md` still describes `legal_matters` and a score on the page. It is not a rulebook.
- **R1.10** There is no prompt file for the Activity Collector or the list builders except this guide and `docs/BOTS.md`.

<a id="r2"></a>
## R2. Page snapshot, 2026-10-27

- **R2.1** This snapshot is what the live page returned that day. It is not a second set of rules.
- **R2.2** The live firm page is filled in the browser. `firm_page` returns the payload. `launch/js/company.js` draws it. `launch/copy.json` holds the labels. A fetch of `https://regretamin.com/vc/sequoia/` returns the shell; the figures below are from calling `firm_page('sequoia')` and `firm_page` field lists, plus the a16z counts from the same tables.
- **R2.3** The problem numbers point at the dated record `docs/RULES_AUDIT.md`.

What Sequoia’s payload contains:

- **R2.4** `firm_page('sequoia')` returned `open: true` (the paywall switch is off).
- **R2.5** Name: Sequoia Capital. HQ: Menlo Park, CA. Website: sequoiacap.com. Assets string: `$82.2B`.
- **R2.6** Hero facts that still exist in the payload: HQ, and Regulatory AUM `$82.2B`. The hero cards are not drawn.
- **R2.7** Sections returned: overview 4, checks 10, legal 6, press 5, people 15, funds 9, timeline 1. No LP section and no founders section.
- **R2.8** The browser drops `checks` from the full-report section list and combines press and timeline into News.
- **R2.9** Activity: active, 10 deals in the last 12 months, 10 deals total, latest fund Sequoia Capital Fund, L.P. at $22.7B, latest deal Blacksmith, 8 public founder reviews.
- **R2.10** a16z, from the same tables: 13 people shown, 26 legal rows shown, 81 investments, 11 of 21 reviews public, 87 check-detail facts, one current score row that the page does not draw.

<a id="r3"></a>
## R3. Who collects what (snapshot 2026-10-27)

| Rule |  Bot | What it is allowed to do | Where it lands |
|---|---|---|---|
| **R3.1** | List builders | Choose firms for the queue. No written method. | `research_queue.list_source` |
| **R3.2** | Researchers (`toxy-researcher-*`) | Send a dump. It does not write the page. | `bots.research_submissions` |
| **R3.3** | Researcher 3 | Paid checks and visitor requests first. | same, plus `ondemand_jobs` |
| **R3.4** | Enricher (`toxy-enricher`) | The only bot that publishes a page, at ingest. | `bots.research_enrichments`, then the page tables |
| **R3.5** | Checker | Named in `docs/DATA_RULES.md`. No separate publish path. | holding area |
| **R3.6** | Activity Collector | Filled Y Combinator investments (`source_system = activity_collector_2026_10_25`). No written spec. | `investments`, `portfolio_companies` |
| **R3.7** | Friend’s `portal-night-bot*` | Can submit dumps. Feedback text is only attached for that bot. Does not publish. | holding area |
| **R3.8** | One-off migrations | Sequoia’s `$82.2B`, Sequoia’s 10 deals, press and timeline check marks. | the named tables |

- **R3.9** Sites the rules name: sec.gov (IAPD / Form ADV, including Item 5F, and EDGAR Form D), CourtListener, PACER, uscourts.gov, FINRA, the FCA, OFAC and `sanctionssearch.ofac.treas.gov`, the UK sanctions list, `sanctionsmap.eu`, the UN list, GLEIF, Companies House. OpenCorporates is not named. Firm sites, TechCrunch, Bloomberg, Reuters, and Axios appear as real lab URLs. X and LinkedIn appear as review sources in the gold examples.
- **R3.10** There is no written rule that a given element must come from a given site, except the source filter (sec.gov and courts for government hosts; search pages refused).

<a id="r4"></a>
## R4. Overview (old, being removed)

- **R4.1** The text below describes the old Overview, kept for reference until the build.
- **R4.2** Rows in a fixed order: HQ, Legal name, Registration, Founded, Owners, Recent changes, then anything else that was not hidden. Sequoia returns 4 overview items before that rewrite.
- **R4.3** `firm_profile_facts` where `section = overview`, not hidden, with a source. `company.js` `overviewRows` rewrites them while drawing.
- **R4.4** Enricher, from Form ADV and the firm’s own pages. Labels in the gold example include Headquarters.
- **R4.5** One label, one value, one source. Headquarters, Founded, and Regulatory AUM conflict instead of duplicating when the value differs. Notes and over-long text are rejected for new items.
- **R4.6** Hidden labels: Other names, Type, Staff, Private funds, Legal entity, Sanctions screening, empty, “Not found.” A row with no source is not returned.
- **R4.7** RULES_AUDIT 15. The label `Overview` is not hidden. Eight lab firms have 3 such paragraphs each.

<a id="r5"></a>
## R5. Old notes

- **R5.1** Old note (was in B10.1): cards grouped into board, moves, and officers. Sequoia returns 15 people.
- **R5.2** Old note (was in C6.5): a count with no itemized rows said details are coming and linked a CourtListener search of the legal name.
- **R5.3** From B2.6: 4,025 queue rows have no `list_source` (RULES_AUDIT 23).
- **R5.4** From B3.1: Sequoia shows “Sequoia Capital” and “Menlo Park, CA.”
- **R5.5** From B3.3: (Snapshot, Overview now removed: the enricher could publish an overview fact labelled Headquarters.)
- **R5.6** From B4.6: (Snapshot, Overview now removed: Overview paragraphs could contain a CRD that these pills do not show, RULES_AUDIT 15.)
- **R5.7** From B5.6: Five lab firms have a stored current score, including a16z.
- **R5.8** From B6a.1: Sequoia is active.
- **R5.9** From B6a.3: Sequoia’s deals were copied from timeline lines (`sequoia_timeline_deals`). Other deals: unknown, except Y Combinator’s activity collector.
- **R5.10** From B6b.1: Sequoia: 10.
- **R5.11** From B6b.6: Six lab firms are at 0.
- **R5.12** From B6c.1: Sequoia: Sequoia Capital Fund, L.P., $22.7B, 5 Feb 2026.
- **R5.13** From B6c.3: Sequoia’s two amounts were written by the one-off migration from EDGAR Form D. Other `funds` rows: unknown, often older imports.
- **R5.14** From B6c.6: Lightspeed has 64 fund rows and 4 profile lines. Accel has profile lines and no `funds` row.
- **R5.15** From B6d.3: Sequoia’s display string was set by the one-off migration to `$82.2B`.
- **R5.16** From B6d.6: Four lab firms have a null helper result. Greenoaks returns `$18.27`.
- **R5.17** From B6e.1: Sequoia’s latest is Blacksmith.
- **R5.18** From B6e.1: Sequoia has 10.
- **R5.19** From B6e.5: The lock is off, so it is open.
- **R5.20** From B8.1: Sequoia returns 9.
- **R5.21** From B8.3: Sequoia’s tile amounts were a one-off from two Form D filings.
- **R5.22** From B8.5: Sequoia’s raw Item 5F lines were hidden by the one-off migration.
- **R5.23** From B9.3: Exact registry for each Accel LP: the row’s `source_url`. Not re-fetched for this guide.
- **R5.24** From B9.6: 33 names are in both homes. Accel’s Adams Street row is the example.
- **R5.25** From B10.6: Greenoaks still shows “Board seat: Neil Mehta…”.
- **R5.26** From B12.1: Sequoia’s payload has 5 press rows and 1 timeline row.
- **R5.27** From B12.6: 13 lab links are in both tables. The lab marks were set by `20261027221100_news_one_list_data.sql`, not by a bot.
- **R5.28** From B13.1: Sequoia’s count is 8.
- **R5.29** From B13.6: Khosla has 4 stored and 0 shown.
- **R5.30** From B16.4: The lock is off, so opening a lab page does not spend a credit.
- **R5.31** From B17.2: Live value `false`.
- **R5.32** From C0.6: No bot currently updates the pill.
- **R5.33** From C1.3: Which bot ran them for a given Clear pill: unknown.
- **R5.34** From C1.6: Five lab firms are Clear with 0 `sanctions_checks` rows. Accel is one.
- **R5.35** From C2.3: Unknown which bot last set the lab pills.
- **R5.36** From C4.1: a16z’s stored count is “1 open probe.”
- **R5.37** From C4.6: MIO’s pill says 2 actions while `regulatory_records` is 0.
- **R5.38** From C7.3: Unknown bot for the stored pills.
- **R5.39** From C9.3: Unknown which bot screened them.
- **R5.40** From C9.6: Accel’s Schedule A sentences were hidden as people and did not become a check.
- **R5.41** From C10.3: Unknown bot.
- **R5.42** From C10.5: a16z is Worth knowing from the hand migration.
