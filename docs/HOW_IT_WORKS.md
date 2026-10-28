> Dated record, not the rulebook. The only rules are in [docs/PAGE_DATA_GUIDE.md](PAGE_DATA_GUIDE.md). Where this file disagrees with that guide, the guide wins.

# How Regretamin works (plain-language guide)

Written 2026-10-26 for the owner. It explains the whole system end to end without code. Each part points to the
detailed doc. If this guide and a detailed doc ever disagree, the detailed doc and the database are right; fix this guide.

## 1. What the product is
Regretamin (regretamin.com) helps founders background-check a VC firm before taking its money. Each firm has one page,
`/vc/<slug>/`, with sections such as People & board seats, Funds, Overview, Limited partners, Legal & regulatory,
News (press and timeline together), What founders say, Deals and the 10 checks. A visitor sees a summary. Spending a credit (free or paid)
unlocks the full page. Checks and Full report are two views of that same page. (On 2026-10-26 the database had 10,276 firms that were not deleted, and 10,275 of them were published.)

## 2. The bots (who collects the data)
Researchers only **collect**. What they send stays in the holding area (section 3) and is not copied onto a page.
The Enricher (`toxy-enricher`) is the only bot that writes a public firm page, and it does that at ingest (section 7).

| Bot | What it does | Where its data lands |
|---|---|---|
| Researchers (`toxy-researcher-*`, plus the friend's `portal-night-bot*`) | Research a firm and send a full "dump" (`submit`) | `bots.research_submissions` |
| Researcher 3 (`toxy-researcher-3`) | Handles paid checks and "Request this firm" requests first (docs/ON_DEMAND.md, docs/FIRM_REQUESTS.md) | `bots.research_submissions` |
| Enricher (`toxy-enricher`) | Adds structured items to a firm, section by section (`enrich`), logs every search, and publishes accepted items onto the page at ingest | `bots.research_enrichments`, `bots.search_log`, then the page tables |
| List builders | Pick which firms to research next, including firms visitors asked for | `research_queue`, `firm_requests` |
| Checker / Activity Collector | Covered by the same data rules (docs/DATA_RULES.md) | holding area |

Every bot sends through one door, the `research-ingest` Edge Function, with its own key. A reply tells the bot what was
accepted and what was refused and why (`bot_feedback`). That way the bot learns.

A researcher (`research_submit`) can upload at most 20 dumps a minute for its own `bot_id`. If the reply is
`rate_limited: max 20 uploads per minute per bot, retry shortly`, nothing was stored. Wait and retry the same upload.

## 3. Holding area vs live data
* **Holding area** (`bots.research_submissions`, `bots.research_enrichments`): what bots sent, kept exactly as sent. Never
  edited and never shown to the public.
* **Live data**: the page tables (people roles, profile facts, legal items, timeline, press, reviews, funds, deals,
  check rows, plus `fact_sources`, which holds the source links). Only these are shown on the site.
* Data moves from holding to live **only** through the checker. Since 2026-10-27 that happens at ingest, and only for
  `toxy-enricher` (section 7). A researcher upload does not write a page. Other bots' enrich calls stay in the holding tables.

## 4. Data and date rules (docs/DATA_RULES.md, docs/SOURCE_TIERS.md)
* **One fact per item.** Each item has its own fields (e.g. a person: name, role, kind, since, source) and a source link.
* **Sources:** every item needs a real link. Government sites count only for sec.gov and the courts. Search-result or
  chatbot pages are not sources. Sources are tagged *trusted* (regulators, courts, registers, sanctions lists, government)
  or *other*. A fact with no usable source is kept but hidden (`needs_source`) until a source is added.
* **Notes are never published.** Search logs, counts and reasoning go in `{"note": "..."}` inside a section, or in the top-level `notes` string or array of strings. The checker keeps each one (`notes_kept`) in `publish_checks` and does not put it on the page. Top-level `notes` are saved only for the 10 lab firms.
* **Deals on the 10 lab firms.** A new timeline line that names a company, a dollar amount, and a round is also stored as an investment. The timeline row stays. Other firms are unchanged.
* **Sequoia timeline deals.** `sequoia_timeline_deals(false)` lists the deal lines. `sequoia_timeline_deals(true)` copies them into investments. The timeline rows stay. No other firm is read.
* **Sequoia funds.** The SEC assets figure used for Sequoia is `firms.aum_display` (`$82.2B`). Duplicate raw AUM lines and the long bot note are hidden and kept, with a backup copy. Nothing is deleted.
* **Dates:** single dates are `YYYY`, `YYYY-MM` or `YYYY-MM-DD`. A month-only date is never padded to `-01`. Timeline ranges
  such as `May–Jul 2025` may stay as they are. Ambiguous numeric dates (e.g. 03/04/2025) are never converted automatically.
* **The checker, per item:** checks the shape and source → looks for a duplicate already on the page (a duplicate adds
  its source to the existing item, "merged") → flags a different value as a *conflict* (the page keeps its value until
  the winner is chosen; which value is shown is docs/CONFLICT_RULE.md) →
  records a verdict for every item in `publish_checks` (published, merged, conflict, rejected, note, held).
* **Leads are never public.** Leads, allegations and "fix this" requests are **held** for a person to review. They are
  never shown and never labelled "Lead (unverified)". On the 10 lab firms, a lead with no source is rejected, an allegation without a court or regulator document is rejected, and a conflict is copied onto `conflict_weekly`. A fix that cites sec.gov is listed there and does not overwrite the page.
* **Add only.** Publishing only adds items or adds sources. It never resets a check back to "Not checked yet" and never
  deletes a page row.
* **Several rows for one firm:** items are merged one by one across all of the firm's waiting rows. The newer row wins and
  the older row's source is added to the same item.
* **Old-format rows** (the enrichments from before the rules, ids below `data_rules_from_enrichment_id`) go through the
  same rules. Anything unreadable is held with a reason. Nothing is dropped silently.
* **News is one section on the page.** Press and timeline stay stored as they are. The page combines them into News when it draws: the same link is one card, headlines that share an event and a name within about 7 days are one card, and items dated before 2023 are left off that section. This cutoff, this link merge and this story grouping apply only to News. The same date with a different link is not, by itself, a merge.
* **Own media:** a founder quote or press item from the firm's own site, podcast or channels is labelled "Own media" (not independent).
* **Scores** follow docs/toxy-score-v2-rules.md (start full, lose points only for verified evidence, rates not counts). The same rules, the score function, and the old `/scoring/` page are copied under `score/` from the commit just before the old website was removed. That copy is not what the live site runs.

## 5. Locked, removed and hidden items
* **Locked** (`locked_rows`): an item a person has cleaned up or approved. Publishing never changes it, never adds a
  source to it, never corrects it and never re-adds it.
* **Removed** (`record_removed`, `removed_items`): an item a person took off a page, recorded with a reason. It is also
  locked and hidden, so a bot cannot bring it back.
* **Hidden** (the `hidden` flag with reason, time and who did it): the row stays in the database but is not shown. Publishing can never
  unhide a row. Only `restore_hidden` can do that, and it is fully restorable.
* **Edits in place** (`edit_in_place`): fix a live row where it sits, with a backup copy in `cleanup_backup`. Undo with `undo_edit_in_place`.
* Nothing is deleted without your approval. Backups of changed rows go to `cleanup_backup`.

## 6. Duplicates (docs/DEDUPE.md)
Two pages for the same firm are merged with `merge_firms`. The extra page is soft-deleted, its old address redirects (301)
and its names stay searchable. Inside a page, each item has a stable key (person, fund, legal case…), so the same fact
merges instead of appearing twice. `stable_key_collisions()` lists the existing collisions; they are reported, never merged automatically.

## 7. Publish, approvals and undo (since 2026-10-27)
`toxy-enricher` publishes at ingest. There is no batch approval for that path, and a failed page check does not roll
that write back. `on_page` in the enrich reply is true only when this enrichment published or merged at least one item.
A published firm slug is not enough.

Researcher uploads (`research_submissions`) do not write a page. The two upload triggers that used to copy checks and
facts are closed. A submissions batch does not write a page either. Other bots' `enrich` calls fill `bots.research_enrichments`
only.

The research queue is a to-do list. Inserting a row does not create a firm. Linking a visitor request
(`firm_request_link`) does not create a firm. The link and the to-do stay. The page appears when the Enricher publishes.
A signed-in admin cannot write firm or page tables directly. Hand tools (`edit_in_place`, `record_removed`,
`restore_hidden`, `merge_firms`, `rename_firm_slug`) stay, and they run with the service key.

Batches remain for rows that are still waiting, and for undo of a batch that already ran:

1. **Create a batch:** `create_publish_batch(id, 'enricher' or 'submissions', bot name pattern)` collects the firms with
   waiting data.
2. **Dry run:** `dry_run_publish_firm(id, firm)` publishes that one firm for real *inside a transaction that is rolled back*,
   with the same page check as before. It replaces only that firm's dry-run row. `dry_run_publish_batch(id)` does this for
   firms that have no dry-run row yet, or whose submissions, enrichments, or edits are newer than that row's check time.
   Each call handles at most one firm unless you pass a higher limit, leaves every other firm's row in place, and says how
   many firms are still waiting. Only one dry run runs at a time, and each firm check stops after 20 seconds. The check is:
   * no section goes missing or shrinks
   * no new duplicates or stable-key collisions
   * no increase in rule violations
   * every alert raised is explained (a section grew by exactly the number of items the batch added there)

   A firm that fails is **held**, with its reasons. The rest are marked **live**. Nothing is kept from a dry run except the report.
3. **Read the report:** `publish_batch_summary(id, 'dry')` shows the firms going live, the items by section, the held
   firms and why, and the blocked items (held or conflicting).
4. **Go / no-go:** only Alex approves: `approve_publish_batch(id, 'alex')`.
5. **Run:** `run_publish_batch(id)` publishes again, firm by firm, with the same checks. A firm that fails now is rolled back and held.
   Every row the batch adds is stamped with the batch id.
6. **Undo:** `undo_publish_batch(id)` hides every row the batch added, takes back the founder reviews it added (made
   not public) and puts back any value it overwrote (from the `cleanup_backup` copy). It also removes the source links it
   added. Source links have no hidden flag, so those link rows are removed after a copy is saved in `cleanup_backup`. The check
   history (`publish_checks`) is always kept. A submissions batch does not write check rows.

A researcher upload does not finish a page. Paid on-demand still marks its job done when valid research is stored, and
the ready email can go out, but the public page is filled only when `toxy-enricher` publishes.

## 8. The single page builder
* **Data** comes from the database. `firm_page()` returns each section's items and counts. The full static site is built from `published_site_bundle()`.
* **Ready-made details.** `firm_page_cache` stores the full `firm_details` payload for a firm (every fact, not a locked slice). `unlock_firm`, which `firm_page` calls, reads that row when it is there and builds it, then stores it, when the row is missing. A publish, an enricher write, or a fact or legal edit deletes the row. The trigger does not rebuild the page. Whether this visitor can see it is still decided per visit, outside the cache.
* Shared features use one shared module on every page.
* **Look and words** come from the repo: `launch/copy.json` (all text, section titles, order), `launch/style.css`,
  `launch/build.py` (markup) and `launch/js/*`. There is one template for every firm. On Cloudflare, `launch/functions/vc/[[path]].js`
  serves `/vc/<slug>/` for every published firm, and `launch/edge/firm.mjs` mirrors the builder (a test checks that they match).
* **Lab-only is the default build.** `LAB_ONLY` defaults to 1. `launch/build.py` then writes static pages for the 10 lab firms only: a16z, y-combinator, sequoia, lightspeed, generalcatalyst, plugandplay, accel, greenoaks, khosla-ventures, mio-partners. With the database keys set, it calls `firm_meta` for those slugs and does not walk the full sitemap. `LAB_ONLY=0` is the all-firms build. CI uses the default. A full build and deploy runs only when the Pages workflow is started by hand with input `rollout` true, which is only for Alex saying "roll out". A push that changes only `docs/**` or markdown does not build. The changelog line for a change goes in that change's pull request.
* **A lab deploy does not remove other firm pages.** Wrangler, run from `launch/`, uploads `launch/functions` with the static directory. The `/vc/` function renders every published firm from `firm_meta`, and `sitemap.xml.js` renders the full sitemap. Those static files are not what serves the other firms. `scripts/pages_deploy.sh` refuses to start if the function files are missing or the firm-directory count is wrong. It publishes preview first, and publishes production only after that preview still returns the non-lab firm `founders-fund` and the functions sitemap still lists its first thousand firms. `founders-fund` itself sits outside that thousand-row cap. If that check fails, production is not deployed. Deploys share the `pages` queue and are not cancelled. Each pull request has its own queue.
* A section shows only if it is listed in `copy.json` **and** the database returned it. See launch/HOW-TO-CHANGE.md for what to edit for each kind of change.
* **Overview, display only.** The browser hides Other names, Type, Staff, Private funds, Legal entity, Sanctions screening, and empty or "Not found" rows, strips CRD and SEC file numbers, and shows what is left as HQ, Legal name, Registration, Founded, Owners, and Recent changes. The count matches those rows. Nothing is rewritten in the database.

## 9. Alerts and routines
* **Section-count alerts** (`section_count_alerts`): after every publish, each section's item count is compared with the
  last count. An alert is raised when a section drops, or jumps by more than 20 or by more than 1.5×. These alerts are internal and never
  emailed to visitors. A deliberate hide or restore refreshes the counts, so it does not raise a false alert. In a batch, a jump that equals what the
  batch added counts as explained. A drop always holds the firm.
* **Scheduled jobs (pg_cron on the database):**
  * `regretamin-ondemand-tick` every 2 minutes: refunds paid checks not done within 24 h and sends ready/refund emails.
  * `regretamin-refill-yearly` hourly: refills the checks on yearly plans.
  * `downgrade-lapsed-payments` hourly: downgrades unpaid plans.
  * `bots-search-log-retention` nightly: deletes `bots.search_log` rows older than 30 days that are tied to a firm. Rows with no firm are left for a later decision.

  There is **no** scheduled publishing.
* **Emails** go out as plain text from `support@regretamin.com` (Resend): ready, request ready, refund and received.

## 10. Gold examples (docs/GOLD_EXAMPLES.md)
There are exactly two reference pages that show what a good page looks like: **Y Combinator** (`/vc/y-combinator/`) and **a16z**
(`/vc/a16z/`). Bots compare their output against these before submitting. Accel is no longer a gold example. Its old mistakes stay in the doc only as "wrong" examples.

## 11. Where things live
| Thing | Where |
|---|---|
| Code, docs, tests | GitHub `mindgame77/regrettamine` (merging to `main` deploys the 10 lab firm pages to regretamin.com; a full deploy is the manual `rollout` input) |
| Database, Edge Functions, scheduled jobs | Supabase project `sxxgvkdwgiouyqciztec` |
| Database changes | `supabase/migrations/` (applied in name order, tested in CI on Postgres 16) |
| Bot door | Edge Function `research-ingest` |
| Holding area | `bots` schema: `research_submissions`, `research_enrichments`, `search_log`, `research_gaps`, `enrichment_rows`, `ingest_keys`, `ingest_rate`, `ingest_settings`, `bot_feedback`, `fact_source_additions`, `firm_lps`, `firm_lp_summary`. `research_queue` stays in `public` |
| Verdicts per item | `publish_checks` |
| Batches | `publish_batches`, `publish_batch_firms` |
| Backups and undo copies | `cleanup_backup` |
| Locks / removed | `locked_rows`, `removed_items` |
| Alerts | `section_count_alerts`, `section_counts` |
| Switches | `bots.ingest_settings` (`auto_promote_enrichment` no longer gates `toxy-enricher`; that bot publishes at ingest) |
| Old website functions | Dropped. The launch site, edge functions, cron, and other database functions did not call them. `my_billing`, `access_tier`, `set_fund_alert_kind`, `set_watch_alert_kind`, `watch_fund`, `unwatch_fund`, and `is_admin` stay. Recreate from `supabase/rollbacks/20261028060000_drop_old_site_rpcs.sql` |
| Detailed docs | DATA_RULES, CONFLICT_RULE, ENRICHER, SOURCE_TIERS, DEDUPE, ON_DEMAND, FIRM_REQUESTS, GOLD_EXAMPLES, data-model, toxy-score-v2-rules |
| Old website scoring | `score/` (verbatim copy of the score function, its tests, the rules, and the old `/scoring/` page, from commit `5584274`) |
