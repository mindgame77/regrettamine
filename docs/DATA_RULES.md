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
3. **Flags conflicts** instead of overwriting: same person with a different role, same fund/figure label with a
   different value, an HQ / Founded / Regulatory AUM that differs from the page. The page keeps its value.
4. **Never publishes notes.**
5. **Records every verdict** in `publish_checks` (`published`, `merged`, `conflict`, `rejected`, `note`) with the reason.
   The `enrich` reply returns the rejects, notes kept, conflicts and counts, so the bot can resend fixed items.

## 3. Existing data

Enrichments received before the rule (ids below `ingest_settings.data_rules_from_enrichment_id`) keep the old path, so
pages do not change until the cleanup, which is done firm by firm with a before/after (a16z and YC first).
Nothing is deleted without Alex's approval. `people_note_guard` (hidden note-like people rows) stays.
