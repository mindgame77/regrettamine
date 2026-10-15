# Research workbook import: Oct 14, 2026

Four workbooks were loaded into the existing schema. The workbook isn't kept as a source; each fact keeps its own source URL. Real = sheet status 'verified' + source URL + checked date; everything else is test. Workbook AI text was loaded as draft (not approved). Nothing existing was overwritten.

| Firm | Match | Facts real | Facts test | Funds | Roles | Conflicts |
|---|---|---|---|---|---|---|
| General Catalyst | existing: generalcatalyst | 71 | 35 | 40 | 82 | score 89 -> 98.9 |
| Lightspeed Venture Partners | existing: lightspeed | 91 | 21 | 63 | 123 | score 88 -> 100.0 |
| Sequoia Capital | existing: sequoia | 118 | 20 | 50 | 58 | score 89 -> 100.0 |
| Plug and Play Tech Center | new (test, unpublished) | 14 | 44 | 7 | 53 | - |

## Not loaded: no place in the schema (to discuss)

| Field | Rows | Meaning |
|---|---|---|
| cik | 305 | SEC CIK per entity/fund |
| lei | 51 | Legal Entity Identifier |
| context | 36 | free-text context notes |
| career_stint | 27 | partner career history |
| stated_focus_sector | 24 | firm-stated focus (sector) |
| political_donation | 22 | partner political donations (FEC) |
| founded_company | 21 | companies a partner founded |
| company_number | 17 | state/UK company registry numbers |
| prior_firm | 10 | partner prior firms |
| team | 10 | partner team (seed/growth) |
| deal_led | 9 | deals led by a partner |
| lobbying_spend | 7 | lobbying disclosures |
| community_report | 6 | community/forum founder reports |
| stated_geography | 5 | firm-stated geography |
| negative_alias | 5 | names that are NOT this firm (disambiguation) |
| stated_focus_stage | 4 | firm-stated focus (stage) |
| investing_partner_count | 4 |  |
| team_size | 4 |  |
| lobbying_issue | 3 |  |
| partner_statement | 3 | public statements by partners |
| entity_status | 3 | registry status of an entity |
| adverse_event_candidate | 2 |  |
| conflict_candidate | 1 |  |
| employee_sentiment | 1 |  |
| platform_team | 1 |  |
| firm_claim_contradiction | 1 |  |

Sheet-level data not loaded: per-fact confidence, # sources, # independent roots, score_moving, firm_controlled, lens_reasons; per-source trust_tier, junk, archive_url, published_date; the Partners matrix (cross-links only; roles were loaded from Facts); the tabs Not found, Human queue, Run log, Cost, and 'What the firm says about itself'; Summary extras (worst-case floor, confidence, sources reliable %, red banner, insufficient-data flag).

## Update Oct 15, 2026: needs_proof, extra fields, no workbook scores

- Reclassified with the three-value rule (see DATA-ARCHITECTURE.md): verified + URL + date = real, excluded = test, everything else needs_proof. The fields in "Not loaded" above now live in vc_entity_identifiers, vc_partner_history, vc_political_activity, vc_firm_claims and vc_context_notes.
- Removed from the earlier import (workbook judgments, not facts): 4 vc_scores rows `research-draft` (with their 47 score parts and 51 score inputs, by cascade), 12 vc_ai_summaries by `research-bot` (verdict, verdict sub, summary per firm), 3 vc_fact_conflicts rows comparing workbook scores to ours. Not imported at all: Score sheet, Summary extras, confidence, trust tiers, # sources, # independent roots, score_moving, lens_reasons, Partners "Judge summary", and the fields adverse_event_candidate, conflict_candidate, firm_claim_contradiction, employee_sentiment.
- Plug and Play stays unpublished (firm row needs_proof): its real facts do not cover our score inputs (portfolio count, founder accounts, investing partners, media, fund size), and the site has no report for it.
