# Data rules (all bots, all data kinds)

Approved by Alex on 2026-10-25. This applies to every bot that sends data: the researchers (`submit`), the list builders
(`firm_requests`), the Enricher (`enrich`), the Checker and the Activity Collector.

## 1. Bots only collect, into the holding area

Bots never write to page tables. What they send is stored as-is in the holding area (`research_submissions`,
`research_enrichments`) and only reaches a page through the checker below.

**Upload rate.** `research_submit` stores at most 20 submissions per minute for one `bot_id`. The next one in that
minute raises `rate_limited: max 20 uploads per minute per bot, retry shortly` and stores nothing. Wait and retry
that same submit.

**One structured item per fact.** Each item has the fields for its kind, plus a source link:

| Section (enrich) | Item fields |
|---|---|
| People & board seats | `name` (one person), `role`, `kind` = `officer` / `board` / `move`, `company` (board), `since`, `source` |
| Funds | `name`, `amount` (with a number), `currency`, `date`, `source` |
| Overview | `label`, `value`, `source` |
| Limited partners | `name`, `type`, `source` |
| Legal & regulatory | `title`, `date`, `status`, `allegation` (true for leads), `source` |
| Timeline | `date` (`YYYY`, `YYYY-MM` or `YYYY-MM-DD`), `event`, `source` |
| Press coverage | `outlet`, `date`, `headline`, `url`, `snippet` |
| What founders say | `who`, `quote`, `date`, `source` |

**Timeline dates may be informal.** Store single dates as `YYYY`, `YYYY-MM` or `YYYY-MM-DD` (never pad a month-only date
to `-01`), but a range such as `May–Jul 2025` or `2024-09-24/25` is fine as-is. Dates written inside body text that the
design doesn't show as a date don't need the formal format. If a timeline row is undated but its text contains a date, use
that date (e.g. "29 June 2026: Form ADV…" → `2026-06-29`).

`add` / `leads` items send the same object as `value`. A `fix` may send a short string (`correct_value`) for one person's field
or one overview/funds figure. `submit` records keep the dump-1.2 shapes (they were already structured).

**Free text only as a note.** Anything that is not one fact - search logs, counts ("Schedule A lists 14 individuals"),
"matches the surname", reasoning, "no source URL" - goes in `{"note": "..."}` inside a section, or in the top-level
`notes` field. `{"note": "..."}` is one object whose only fact is the string in `note`. Top-level `notes` is either one
string or an array of strings. Each of those is outcome `note`. `notes_kept` counts it, and it is saved on
`publish_checks`, only when the firm is one of the 10 lab firms. Notes are kept for the team and never published. A blank string is skipped. The old `{"item": "..."}`
free-text form is refused.

## 2. One checker at publish

Every publish path goes through the same rules. The live path is `promote_enrichment`, and only `toxy-enricher` calls it
at ingest. A researcher submission is not published onto the page. Per item the checker:

1. **Checks type and shape** for the section (fields above), the source (a real URL; `.gov`/`.mil` only sec.gov and courts),
   dates, AUM has a number, and that no text field is a note: bot bookkeeping phrases, a URL inside the text, or text that is
   too long. A person's `name` must be one person (no digits, brackets, "and", lists, more than 6 words).
2. **Dedupes** against rows already on the page (same person + kind, fund/fact label, LP name, legal title, timeline
   date + event, press URL). A duplicate adds its source to the existing row (`merged`) instead of a second row.
   Press and timeline stay separate rows. The page combines them into News when it draws (see below). That
   combination is not a publish rule, and no other section uses it.
3. **Flags conflicts** instead of overwriting: same person with a different role, same fund/figure label with a
   different value, an HQ / Founded / Regulatory AUM that differs from the page. The page keeps its value until the
   winner is chosen. Which value is shown, and that the other value is kept with its source, is docs/CONFLICT_RULE.md.
4. **Never publishes notes.**
5. **Records every verdict** in `publish_checks` (`published`, `merged`, `conflict`, `rejected`, `note`, `held`) with the reason.
   Fixes, leads and allegations are `held` (never published; leads are never public).
   The `enrich` reply returns the rejects, notes kept, conflicts and counts, so the bot can resend fixed items.

## 3. Existing data

Enrichments received before the rule (ids below `ingest_settings.data_rules_from_enrichment_id`, the "old format") go
through the same rules at publish: items that pass are published, the rest are logged with an `old format:` reason, and a
row with nothing readable is `held`. Nothing is dropped silently.
Nothing is deleted without Alex's approval. `people_note_guard` (hidden note-like people rows) stays.

## 4. News is one section on the page (display only)

Bots keep sending Press coverage and Timeline as two sections, and publish keeps them as two tables. `firm_page` returns a press row only when `press_item_firms.check_mark` is `checked_correct`, and a timeline row only when `timeline_events.check_mark` is `checked_correct`. The firm page draws one **News** section by combining those rows in the browser and sorting them by date. Legal stays its own section. `checked_wrong` and `not_checked` stay stored and are not drawn. Nothing is deleted, and nothing is copied into a News table for this.

These two rules apply **only when News is drawn**. No other section drops old rows, and no other section merges on a link:

1. **One card per link.** A press item and a timeline item with the same normalized link are one card. The timeline
   tag (Court, Filing, Regulator, People, Fund) is kept on that card. Normalization is lowercase, without the scheme,
   `www.`, query, hash or a trailing slash. A timeline event dated before 2023 does not fold into a card dated 2023
   or later, or into a card with no date. Two timeline events that share a link stay two cards when their dates differ.
   The same date with a different link is not, by itself, a merge.
2. **One card per story.** After the link merge, News groups items whose dates fall within 7 days when the headlines
   share an event word and a name (a company, a fund, or an agency such as DOJ). The firm’s own name is not enough on
   its own. A date that is only a year can join one group from that year whose days already sit within 7 days; it does
   not join two groups that are further apart. The card keeps the newest dated headline, lists each outlet, and adds
   an “N outlets” note when more than one outlet is grouped. Headlines that do not share those terms stay separate cards.
3. **Since 2023.** Items dated before 2023 are not shown in News. They stay stored. Undated items are shown.

## 4a. Overview rows are cleaned when the page draws (display only)

The stored overview facts stay as filed. `launch/js/company.js` rewrites them only while drawing the Overview section. No other section uses these rules.

Hidden rows: Other names, Type, Staff, Private funds, Legal entity, Sanctions screening, and any row that is empty or "Not found". CRD numbers and SEC file numbers are removed from the rows that stay. A row whose label is the entity name (for example `Y COMBINATOR MANAGEMENT, LLC`) is shown as `Legal name:` plus that name in title case. Registration is shortened to `SEC-registered since <year>, active`, or `SEC exempt reporting adviser, active` for an exempt reporting adviser. If Registration is missing and Legal entity holds that status, that text becomes the Registration line. Founders are merged into Founded (`2009 · Marc Andreessen, Ben Horowitz`). The order is HQ, Legal name, Registration, Founded, Owners, Recent changes, then any other overview row that was not hidden. The section count is the number of rows still shown. Source pills stay on the kept rows. A merged row keeps both rows' pills, with the same link once.

## 5. The Enricher publishes at ingest
`toxy-enricher` publishes when its enrich call is stored. There is no batch approval on that path. Other bots' enrich
calls stay in the holding tables. A researcher upload does not write a page. Batches remain for rows that are still
waiting, and for undo. See docs/ENRICHER.md "Publishing" and docs/HOW_IT_WORKS.md.
