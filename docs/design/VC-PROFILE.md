# VC profile structure, with a16z as the benchmark (DRAFT, nothing applied)

Andreessen Horowitz (a16z) is the reference profile. It's the most complete report we have (32 evidence cards, 14 legal matters, 18 press items, 39% coverage). Every other VC is measured against it with the completeness checklist below.

Files
- `a16z-benchmark.json`: the a16z report re-expressed in the new shape, built from `data/funds/a16z.json` (report of Oct 2, 2026). It has 65 source facts and 41 AI summaries.
- Draft SQL: `regrettamine-audit/supabase/drafts/20261014150000_vc_profiles.sql` (not applied, not run by CI). It builds on the `data_status` and merge-ready drafts.

## Layers

| Layer | Holds | Rule |
|---|---|---|
| `vc_profiles` | identity: slug, name, short name, legal name, SEC CRD, domain, HQ, founded, firm type, publish status, report date, disambiguation note ("Not the $AI16Z token") | root. Every VC-owned row cascades from it. Soft delete with `deleted_at`. |
| `vc_aliases` | names, legal entities, CRDs, domains | used to match firms during merges |
| `vc_source_facts` | true, sourced facts: SEC records, fund facts, legal matters, sanctions checks, press items, board seats, partner moves, portfolio counts, founder experiences | `source_url` + `retrieved_at` are required before a fact can be `real`. Never rewritten by AI. Superseded, not edited. |
| `vc_ai_summaries` + `vc_ai_summary_facts` | verdict, verdict subline, summary, takeaways, score-rule explanations, "why" lines, ask-the-fund questions | every row cites at least one fact. Labeled as AI text in the UI. Marked stale when a cited fact changes. |
| `vc_scores` + `vc_score_parts` + `vc_score_inputs` | computed score, band, range, coverage, rank, parts and inputs | derived from facts by the score worker. Keeps the method version. |
| UI strings (`ui_strings`/strings.js) | section titles, notes, empty states, labels that are the same for every fund | never stored per VC (moved in PR #34) |

## a16z field map (current JSON → new home)

| Section | Current field(s) | New home | Kind |
|---|---|---|---|
| Header | slug, name, short, hq, since, notToken | vc_profiles | identity |
| Header | meta ("SEC adviser · CRD 160489", "AH Capital Management, L.L.C.") | vc_profiles.sec_crd, legal_name + facts `sec_crd`, `legal_entity` | fact |
| Header | updated, method | vc_profiles.report_date, vc_scores.method_version | meta |
| Overview | question | ui_strings `report.question` | site |
| Overview | verdict (variant clear/review/flag/no_data), verdictSub | vc_ai_summaries kind `verdict` (with variant), `verdict_sub` | AI |
| Overview | summary, takeaways[6] (+ evidence tk0–tk5) | vc_ai_summaries `summary`, `takeaway`, cited facts | AI |
| Overview | floats, badges (sanctions, coverage, people) | derived from facts + vc_scores at render | derived |
| Score | scoreShown, scoreExact, band, range, rank, coverage | vc_scores | derived |
| Score | parts[6].name/got/max, inputs[].name/points | vc_score_parts / vc_score_inputs | derived |
| Score | parts[].rule, inputs[].why | vc_ai_summaries `score_part_rule`, `score_input_why` | AI |
| Score | notCounted[3] | facts (type `legal_matter`, counted=false) + AI why | fact + AI |
| Legal | matters[14] (year, text, sub, badge, tone), topLegal, legalGroups | facts `legal_matter` (status, counted, points) + ordering in vc_profile_sections | fact |
| Legal | regulatory.records[3] | facts `regulatory_record` | fact |
| Legal | regulatory.sanctions | fact `sanctions_check` (lists, date, people checked) | fact |
| Fund | fundTab.facts[6] (AUM, funds, staff…) | facts `fund_fact` (Form ADV) | fact |
| Fund | boards.items[8], moves.items[4], media.items[4] | facts `board_seat`, `partner_move`, `media_reach` | fact |
| Fund | boards.note, moves.foot, media.foot | AI summary if fund-specific, else ui_strings | AI / site |
| Public | public.items[18] (publisher, date, headline, url, group, sentiment) | facts `press_item` | fact |
| Public | items[].why | vc_ai_summaries `press_why` → that press fact | AI |
| Portfolio | size, events[11], health[3], litigation | facts `portfolio_size`, `portfolio_event_count`, `portfolio_health`, `portfolio_litigation_rate` | fact |
| Founder experiences | reviews (0 today; hidden until enough verified) | facts `founder_experience` (verified reviews; author kept in user DB) | fact |
| Ask the fund | ask.questions[8] | vc_ai_summaries `ask_question` | AI |
| Footer | footnote, scoreFooter | ui_strings with `{method_date}` vars | site |
| Evidence drawer | evidence.<id> kicker/title/body/rows/sources | body/title → AI summary; sources/rows → facts; derived cards (range, cov, rank, rules, rel) are computed | mixed |
| Merge | (new) | source_system, external_id, import_run_id on every row | merge |

## Completeness checklist (benchmark = a16z)

Each item counts as Present, "No data yet" (shown, not hidden) or Missing. A profile can publish when all required items are present or explicitly marked "No data yet".

| # | Item | Required | a16z |
|---|---|---|---|
| 1 | Identity: name, slug, HQ, founded, firm type | yes | ✓ |
| 2 | Stable id: SEC CRD or legal entity + domain | yes | ✓ CRD 160489 |
| 3 | Aliases (names, entities, domain) | yes | ✓ 5 |
| 4 | Fund facts from Form ADV (AUM, number of funds, staff) | yes | ✓ 6 |
| 5 | SEC enforcement / regulatory records checked | yes | ✓ 3 records |
| 6 | Sanctions check (OFAC/EU/UK/UN), dated | yes | ✓ Oct 2 |
| 7 | Federal courts searched; legal matters with source each | yes | ✓ 14 |
| 8 | Founder-relevant matters grouped and counted/not-counted reasons | yes | ✓ |
| 9 | Score with all 6 parts, inputs, range, coverage, method version | yes | ✓ 95.4, 39% |
| 10 | Verdict + summary (AI, cites facts, approved) | yes | ✓ |
| 11 | Takeaways ≥ 3, each cites facts | yes | ✓ 6 |
| 12 | Public record ≥ 5 press items with sentiment | recommended | ✓ 18 |
| 13 | Partner board seats | recommended | ✓ 8 (sources to link) |
| 14 | Partner moves, last 24 months | recommended | ✓ 4 (sources to link) |
| 15 | Portfolio size + adverse events + litigation rate | recommended | ✓ |
| 16 | Founder experiences (verified) | recommended | No data yet |
| 17 | Ask-the-fund questions | recommended | ✓ 8 |
| 18 | Every fact `real`: source URL + retrieved_at | yes | 42 of 65 (23 board/move/portfolio facts need their source linked) |
| 19 | No open fact conflicts | yes | ✓ none |
| 20 | No stale AI summaries | yes | ✓ |

Completeness score = required present / required total, plus recommended as a secondary %. Stored in a `vc_profile_completeness` view, which the admin page can show per VC.

## Open points
- Takeaway and score-rule fact links in the JSON are best-effort (matched by source URL). They need a review pass.
- Board seats, partner moves and portfolio counts have sources in the old evidence cards but not per item yet. Link them, or keep them `test`.
