# Regretamin data architecture: proposal (DRAFT, nothing applied)

Status: draft for Alex. Nothing below has been applied to Supabase. The only migration applied so far is `ui_strings` (approved, Oct 14, 2026). Current schema facts come from the live project `regrettamine` (read-only query, Oct 14).

## Principles
1. **Three domains with hard edges:** site text, VC database, user database. A row belongs to exactly one domain.
2. **The VC is the root.** `vc_profiles` owns everything about a firm. Every VC-owned table has `vc_id … references vc_profiles(id) on delete cascade`.
3. **Facts and AI text are separate layers.** Facts are sourced and never rewritten by AI. AI text cites fact ids, is versioned, and is reviewed.
4. **Soft delete first:** `vc_profiles.deleted_at`. Removed VCs disappear from public reads at once, and a purge job hard-deletes after 30 days, which cascades.
5. **Users reference VCs and never own VC data.** User rows survive a VC purge as "Removed" (FK `on delete set null` plus a cached name).
6. **No facts in code.** Pages read everything from these tables. JSON in `data/` is only a local fallback and seed.

## Domain 1: Site text
| Table | Purpose |
|---|---|
| `ui_strings(key, variant, condition, text, locale, note, status, updated_at, updated_by)` | **Applied.** Unique (key, variant, locale). Anyone can read; only the service role writes. Bundled fallback is `src/js/strings.js`. |
| `site_config(key, value)` (from `data/site.json`, `gating_policies`) | Company legal details, plan limits, prices (mirrors Stripe). |
| `site_stats` (derived) | Becomes a **view** computed from the VC domain (fund count, sources cited, active matters). Never typed in. |

Rule: if a text is the same for every fund, it is site text, even when it is shown on a fund page (e.g. "Should I take this money?", score part names).

## Domain 2: VC database
```
vc_profiles (root)
 ├─ vc_funds / vc_entities / vc_people / vc_portfolio …   (structured facts, cascade)
 ├─ vc_source_facts            (layer 1: true facts)        ──┐
 ├─ vc_ai_summaries            (layer 2: AI text)            │
 │    └─ vc_ai_summary_facts   (join: which facts each text uses) ─┘
 ├─ vc_scores / vc_score_parts / vc_score_inputs  (score results cite facts)
 └─ vc_events                  (update feed: fact changed / rescored)
```

### vc_profiles
`id uuid pk, slug text unique, name, short_name, hq, since, sec_crd, status ('researched'|'queued'|'partial'), published bool, is_test bool, created_at, updated_at, deleted_at timestamptz null`
- Public reads use the view `vc_profiles_live` (`deleted_at is null and published and not is_test`).
- Purge job (pg_cron, daily): `delete from vc_profiles where deleted_at < now() - interval '30 days'`. The cascade removes facts, AI text, scores and events.

### Layer 1: vc_source_facts (immutable-ish)
`id uuid pk, vc_id fk cascade, kind ('sec_registration'|'sec_enforcement'|'sanction'|'court_case'|'doj'|'news'|'portfolio'|'person'|'aum'|'founder_review'|…), subject (text), value jsonb, source_url, source_type ('sec_iapd'|'sec_edgar'|'ofac'|'eu'|'uk_ofsi'|'un'|'pacer'|'courtlistener'|'doj'|'press'|'firm_site'|'founder'), source_record_id (CRD, docket no., press URL hash), quote text, retrieved_at, status ('current'|'superseded'), superseded_by uuid null, created_by ('worker:sec'|'worker:sanctions'|…|'researcher')`
- **Never AI-rewritten.** A correction inserts a new row and marks the old one `superseded`, so history is kept.
- Unique (vc_id, source_type, source_record_id) where status = 'current'.
- Replaces: `sources`, `fact_sources`, `regulatory_records`, `sanctions_checks`, `filings`, `docket_entries`, `press_items(+_firms)`, `legal_matters(+_firms, _parties)`, `firm_meta_items`, `portfolio_metrics`, `evidence_lines` (rows). Structured tables can stay as typed facts, but each must carry `source_url`, `retrieved_at` and `status`.

### Layer 2: vc_ai_summaries
`id uuid pk, vc_id fk cascade, slot ('verdict.headline'|'verdict.sub'|'summary'|'takeaway'|'evidence.body'|'public.why'|'ask.question'|'score.input.why'|…), position int, text, model text, prompt_version text, generated_at, review_status ('draft'|'approved'|'rejected'), reviewed_by, reviewed_at, stale bool default false, stale_reason text`
- Join table `vc_ai_summary_facts(summary_id fk cascade, fact_id fk → vc_source_facts on delete cascade, claim_ref text)`.
- **Stale trigger:** when a linked fact is superseded or deleted, set `stale = true` on every summary that cites it, and add it to the regeneration queue.
- **Validation (check before approval):** every sentence or claim in `text` has at least one `claim_ref` mapped to a current fact. A summary with zero linked facts cannot be `approved`. No banned words ("safe", "guaranteed").
- Public reads show only `approved and not stale` (the stale policy is configurable: show it with a "being updated" note, or hide it).
- **UI:** AI text carries an "AI summary" label, with a "Sources" disclosure listing the linked facts (URL, retrieved date).
- Replaces: `takeaways`, `ask_questions`, `copy_blocks` (the fund-specific ones), `evidence_cards.body/kicker`, and JSON `verdict`, `verdictSub`, `summary`, `scoreBarNote`, `notCounted`, `public.items[].why`, `parts[].inputs[].why`.

### Scores and events
- `vc_scores(vc_id cascade, version_id, score, band, lo, hi, computed_at)` and `vc_score_inputs(score_id cascade, part, input, value, fact_ids uuid[] or join table)`. The recompute worker writes them.
- `vc_events(vc_id cascade, kind ('fact_added'|'fact_superseded'|'rescored'|'summary_approved'), fact_id null, summary_id null, at)` feeds "Latest updates" and alerts. It replaces `fact_events` and `site_updates`.
- The rendered `report_pages` / `report_bundles` become a cache keyed by vc_id (cascade), rebuilt when facts or summaries change.

### Data workers (planned)
| Worker | Writes | Trigger |
|---|---|---|
| SEC (IAPD/ADV, EDGAR, enforcement) | facts `sec_*` | daily + on request |
| Sanctions (OFAC, EU, UK, UN) | facts `sanction` (match / no match) | daily list diff |
| Courts + DOJ (PACER/CourtListener, DOJ releases) | facts `court_case`, `doj` | daily |
| News / public coverage | facts `news` | daily |
| Score recompute | `vc_scores`, `vc_events` | on fact change |
| AI summarizer | `vc_ai_summaries` (draft) + fact links | on stale / new VC |
| Purge | hard delete soft-deleted VCs older than 30 days | daily |

## Domain 3: User database
| Table | Notes |
|---|---|
| `users` (= `auth.users` + `profiles`) | `profiles.id → auth.users on delete cascade` (exists). |
| `subscriptions`, `payments`, `stripe_events` | Exist; keyed by profile. Failed payment reverts to free after 24h (per the trust-check flow). |
| `checks(id, profile_id null, anon_id null, query, vc_id null → vc_profiles on delete set null, vc_name_cached, result_status, created_at)` | **New.** Saved/free trust checks; replaces `report_views` for the new model. |
| `watchlist(profile_id, vc_id → vc_profiles on delete set null, vc_name_cached, created_at)` | Exists as `firm_id → firms (cascade)`. **Change to set null + cached name**, so the watchlist shows "Removed" when a VC is soft-deleted or purged. |
| `alert_preferences`, `fund_alert_settings` → `alerts(profile_id, vc_id set null, kind, enabled)` | Merge. |
| `research_requests(id, profile_id, query, vc_id null set null, status ('queued'|'in_progress'|'done'|'rejected'), created_at)` | **New**, for unresearched firms. |
| `reviews` (founder experiences), `corrections` | User-submitted. On approval a review becomes a `vc_source_facts` row (kind `founder_review`) that links back. `reviews.firm_id` stays `set null` so user content survives a VC purge. |

"Removed" display: a user row whose `vc_id` is null, or whose VC has `deleted_at` set, renders `vc_name_cached` plus a grey "Removed" pill (`check.status|no_data` style). Its alerts stop.

## Mapping existing tables (live schema)
| Existing | Domain | Target | Change |
|---|---|---|---|
| firms | VC | **vc_profiles** | rename; add `deleted_at`, `status` |
| funds, fund_entities, fund_people, people, investments, portfolio_companies, company_founders, portfolio_metrics | VC | vc_funds / vc_entities / vc_people / vc_portfolio | add `source_url`, `retrieved_at`, `status`; cascade from vc_profiles (people and portfolio_companies are shared today, so they get a vc join) |
| legal_matters, legal_matter_firms, legal_matter_parties, filings, docket_entries, legal_groups, legal_group_items | VC | vc_source_facts (`court_case`, `doj`) + typed legal tables | legal_matters has no firm FK today (linked via legal_matter_firms); make the link cascade |
| regulatory_records, sanctions_checks | VC | vc_source_facts (`sec_*`, `sanction`) | |
| sources, fact_sources, press_items, press_item_firms | VC | vc_source_facts | sources and press_items have no firm FK today; attach them to vc_id |
| evidence_cards, evidence_lines | VC | facts (rows) + vc_ai_summaries (body/kicker) + join | split |
| takeaways, ask_questions, copy_blocks (fund-specific) | VC | vc_ai_summaries | add fact links, model, review |
| copy_blocks (shared text), page_chips, list_items | Site / VC | ui_strings for shared text; facts for per-fund items | split |
| score_versions, score_sections | Site (method) | keep | rules text goes to ui_strings |
| score_results, score_result_parts, score_inputs, score_lines | VC | vc_scores… | add fact links |
| firm_ranks | VC | view over vc_scores | derive |
| fact_events, site_updates | VC | vc_events | site_updates.firm_id is `set null` today → cascade |
| site_stats | Site | view | derive |
| report_pages, report_bundles, report_html_stage | VC (cache) | report cache | cascade |
| profiles, subscriptions, payments, stripe_events, stripe_forgotten_customers | User | keep | |
| watchlist, fund_alert_settings, report_views | User | watchlist / alerts / checks | **firm FK cascade → set null + cached name** |
| alert_preferences | User | alerts | merge |
| reviews, corrections | User → VC fact on approval | keep | corrections.fund_id is cascade today → set null |
| gating_policies | Site | site_config | |
| app_secrets | System | keep | |
| ui_strings | Site | keep | applied |

## Test vs real data

Every content row carries `data_status` (`test` | `real`), default `test`. Tables: vc_profiles/firms and every VC-owned table (funds, people, legal, filings, dockets, regulatory, sanctions, press, sources, evidence, takeaways, score_results, fact_events), vc_source_facts, vc_ai_summaries, site_updates, site_stats, ui_strings. Public pages, RPCs and the build bundle read `data_status = 'real'` only. Test rows show only in preview/staging builds, with the yellow "Mock · example data" badge.

Rules
- A VC fact can be `real` only if it has `source_url` and `retrieved_at` (CHECK constraint, `NOT VALID` so current rows are grandfathered until `retrieved_at` is backfilled).
- The only way to mark a fact real is `promote_source(id)` (service role). It fails without a URL.
- An AI summary can be approved only if it cites at least one fact, and every cited fact is `real` and `current` (trigger on vc_ai_summaries).
- Placeholder, mock or unsourced content is `test`. Derived values (score range, coverage, rank, method card) are `real` when their inputs are real.

Purge: one command, cascade-safe
```sql
select * from public.purge_test_data();       -- dry run: counts per table
select * from public.purge_test_data(false);  -- delete every test row
```
Deleting a test vc_profile cascades to its VC-owned rows. User rows follow their FK rule (watchlist keeps the row and shows "Removed").

Replace workflow (test to real)
1. Worker or editor inserts a fact as `test` with `source_url`, record id/quote.
2. A reviewer checks it; `promote_source(id)` sets `retrieved_at` and `real`.
3. Linked AI summaries get the stale flag and are regenerated from real facts only, then approved.
4. When a fund's facts are all real, the profile goes `real` and publishes. Run the purge to drop leftover test rows.

Draft migration (NOT applied): `regrettamine-audit/supabase/drafts/20261014130000_data_status.sql`. It lives outside `supabase/migrations/`, so migrate.py and CI skip it.

Current counts (live DB, Oct 14, 2026), all with nothing deleted
| Table | Rows | Would be test | Why test |
|---|---|---|---|
| firms | 11 | 0 | all published, is_test = false |
| sources | 87 | 0 | all have URL + verified (retrieved_at missing, backfill needed) |
| site_updates | 7 | 2 | verification = 'toxy' (unverified records) |
| site_stats | 4 | 1 | "funds sanctioned", verified = false |
| ui_strings | 50 | 12 | status = 'planned' (copy for new flow, not live) |
| legal 19, regulatory 13, sanctions 11, press 25, takeaways 36, evidence_cards 197, evidence_lines 557, people 19, score_results 22 | | 0 | |
| filings, reviews, portfolio_companies | 0 | 0 | empty |

Total: 1,058 counted rows, 15 test, 1,043 real. Of the 197 evidence cards, 45 have no sources, but all are derived cards (range, coverage, sources, rank, method), so they are real, not test.

## Merging existing data

The database must stay open to merging data we collected earlier. Draft only; nothing is applied. Draft SQL: `supabase/drafts/20261014140000_merge_ready.sql`.

Rules
- **Origin on every row.** Every content row has `source_system` (for example `toxybase_netlify`, `toxybase_files`, `repo_json`, `sec_iapd`, `courtlistener`, `opensanctions`, `manual`) and `external_id`. `unique (source_system, external_id)` makes re-imports idempotent: an upsert updates the same row instead of creating a duplicate.
- **Firm matching on stable identifiers.** `vc_profiles` match in this order: SEC CRD, then SEC file number, then normalized legal entity name, then primary domain. `vc_aliases (vc_id, alias_type, value, source_system)` holds former names, short names, entity names, domains and CRDs, with `unique (alias_type, lower(value))`. An import that matches nothing creates a new test profile. An import that matches more than one profile goes to manual review.
- **Staging first.** Imports land in a `staging` schema (`staging.vc_profiles`, `staging.source_facts`, etc.) with `data_status = 'test'`. Review then promotes them into `public` through the same `promote_*` path: a fact needs a source URL and `retrieved_at` before it can be real.
- **Conflicts are kept, not overwritten.** When an imported fact disagrees with an existing one (same VC, same fact type, different value), both rows are kept. `vc_fact_conflicts (fact_a, fact_b, field, status open|resolved, resolution, resolved_by)` records the disagreement. AI summaries that cite either fact are marked stale until it is resolved.
- **Versioned migrations only.** Every schema change goes through `supabase/migrations/` (timestamped files, applied by migrate.py/CI). No manual DDL in the dashboard. Imports are scripts, not migrations.
- **Import log.** `import_runs (id, source_system, started_at, finished_at, file_or_url, checksum, rows_seen, inserted, updated, matched, conflicts, errors, run_by, notes)`. Every staged row carries an `import_run_id`, so a whole run can be reviewed, promoted or rolled back (deleted while still test).

Candidate prior sources to map
| Source | What is there | Maps to |
|---|---|---|
| Old Toxy Base, toxybase.netlify.app | earlier fund profiles, legal records, "Toxy" unverified items (the 2 test updates come from here) | vc_profiles + aliases, vc_source_facts (test until re-sourced) |
| /workspace/toxybase files | `raw/` (SEC IAPD `iapd-*.json`, CourtListener `cl-*.json`, OpenSanctions hits, a16z fund and investment lists), `khosla-*` and `gc-independent-dataset.json` research sets, `seed*.sql`, `fp_*.json`, `data-availability.xlsx`, per-fund research HTML | vc_source_facts with source_system per origin; IAPD gives CRD for matching |
| Repo `data/*.json` (`home.json`, `funds/*.json`) | the current 11 published reports | already in Supabase; tag `source_system = 'repo_json'`, external_id = slug + field path |

Order: register sources, then backfill origin on existing rows (`repo_json`), then import IAPD (CRDs make matching reliable), then courts and sanctions, then old Toxy Base last because it is the least verified.

## Migration order (when approved)
1. Add `deleted_at` + `vc_profiles_live` view (alias `firms` → `vc_profiles` via a view during the transition).
2. Create `vc_source_facts`, `vc_ai_summaries`, `vc_ai_summary_facts`, stale trigger, and the validation function.
3. Backfill facts from the existing tables and JSON; backfill AI text from takeaways/ask/evidence/verdicts as `review_status='approved'`, `model='human/legacy'`, with fact links where the evidence ids map.
4. Switch user FKs to set null + cached names; add `checks` and `research_requests`.
5. Repoint build and RPCs to the new views; drop the old tables after a release.
6. Purge job + workers.

## Open questions for Alex
- Decided: the 12 planned ui_strings stay `test` until the new flow ships.
- Decided: `retrieved_at` is backfilled from the report import date, with `needs_refetch = true` so the workers re-fetch each URL later.
- Stale AI text: hide it, or show it with "being updated"?
- Should approved founder reviews become facts automatically, or need a researcher sign-off?
- Should legacy human-written verdicts be labelled "AI summary" or "Editor summary"? Proposal: a `author_type` column ('ai'|'editor') with the label shown accordingly.
- Should the 30-day purge also delete anonymous `checks` rows for that VC, or keep them anonymised?
