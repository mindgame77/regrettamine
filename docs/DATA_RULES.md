# Data rules (all bots, all data kinds)

Approved by Alex on 2026-10-25. This applies to every bot that sends data: the researchers (`submit`), the list builders
(`firm_requests`), the Enricher (`enrich`), the Checker and the Activity Collector.

## 1. Bots only collect, into the holding area

Bots never write to page tables. What they send is stored as-is in the holding area (`research_submissions`,
`research_enrichments`) and only reaches a page through the checker below.

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
"matches the surname", reasoning, "no source URL" - goes in `{"note": "..."}` (or the top-level `notes`). Notes are kept
for the team and never published. The old `{"item": "..."}` free-text form is refused.

## 2. One checker at publish

Every publish path goes through the same rules: `promote_enrichment` (Enricher), `promote_bot_facts` and
`tools/ingest/import_research.py` (submissions). Per item it:

1. **Checks type and shape** for the section (fields above), the source (a real URL; `.gov`/`.mil` only sec.gov and courts),
   dates, AUM has a number, and that no text field is a note: bot bookkeeping phrases, a URL inside the text, or text that is
   too long. A person's `name` must be one person (no digits, brackets, "and", lists, more than 6 words).
2. **Dedupes** against rows already on the page (same person + kind, fund/fact label, LP name, legal title, timeline
   date + event, press URL). A duplicate adds its source to the existing row (`merged`) instead of a second row.
   Press and timeline stay separate rows. The page combines them into News when it draws (see below). That
   combination is not a publish rule, and no other section uses it.
3. **Flags conflicts** instead of overwriting: same person with a different role, same fund/figure label with a
   different value, an HQ / Founded / Regulatory AUM that differs from the page. The page keeps its value.
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

Bots keep sending Press coverage and Timeline as two sections, and publish keeps them as two tables. The firm page
draws one **News** section by combining those rows in the browser. Nothing is copied into another table, and nothing
is hidden in the database for this.

These two rules apply **only when News is drawn**. No other section drops old rows, and no other section merges on a link:

1. **One card per link.** A press item and a timeline item with the same normalized link are one card. The timeline
   tag (Court, Filing, Regulator, People, Fund) is kept on that card. Normalization is lowercase, without the scheme,
   `www.`, query, hash or a trailing slash. A timeline event dated before 2023 does not fold into a card dated 2023
   or later, or into a card with no date. Two timeline events that share a link stay two cards when their dates differ.
   The same date with a different link is not a merge. Several outlets covering one story stay several cards until a
   later data check says otherwise.
2. **Since 2023.** Items dated before 2023 are not shown in News. They stay stored. Undated items are shown.

## 5. Publishing is by approved batch only
Nothing publishes when a bot sends data. A person runs a batch by hand; Alex approves each batch after its dry run.
See docs/ENRICHER.md "Publishing" and docs/HOW_IT_WORKS.md.
