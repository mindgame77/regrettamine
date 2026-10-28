# How the old website scored a firm

This folder is a copy of the scoring logic as it stood immediately before the old website was removed. The source commit is `5584274b99c58f7588f1b9b946eaf2ad53afc94f`, the parent of `83dddc2` (pull request #179, 2026-10-27). The files below are byte-for-byte that commit. Nothing in this folder is what the live site runs.

| File here | Original path |
|---|---|
| `regrettamine/score_v2.py` | `regrettamine/score_v2.py` |
| `tests/test_score_v2.py` | `tests/test_score_v2.py` |
| `docs/toxy-score-v2-rules.md` | `docs/toxy-score-v2-rules.md` |
| `src/scoring.html` | `src/scoring.html` |
| `src/js/scoring.js` | `src/js/scoring.js` |

The score itself is computed only in `regrettamine/score_v2.py`. The public page `src/scoring.html` states the same rules in words. `src/js/scoring.js` does not calculate a score. It is the paid correction form on that page: search for a fund, and send a “what’s wrong” note with a source link.

The database does not contain a scoring formula. The twelve retired website functions were checked before they were dropped. `landing_funds` and `search_funds` only sorted firms that were already scored, using `list_score_exact` (the one-decimal total) and, if that was empty, the whole-number `list_score`. They do not apply the weights, the rate scale, or the bands. The other ten (`open_report`, `fact_record_count`, `firm_id_for_slug`, `public_firm_id`, `carry_anon_views`, `my_report_slugs`, `my_watch_slugs`, `my_watch_alerts`, `my_alert_funds`, `set_fund_alert`) do not read or write a score. Their SQL is not copied here.

## What the score measures

The score runs from 0 to 100. Higher is better. It measures how the fund treats founders, not how many of its companies failed on their own. Version 2 was agreed on Oct 2, 2026.

Every fund starts with full points in each section and loses points only for verified evidence about its own behavior. A source has to have a working link, name the fund, and show the fund’s role. Copycat names, content farms, and anonymous claims are left out. A lawsuit the fund brought is not the same as one brought against it. Missing sources lower a separate coverage figure. They do not change the score.

Bad events are a share of the companies the fund has backed:

| Share of the portfolio | Penalty, as a fraction of that subsection |
|---|---|
| Under 1% | None |
| 1% up to but not including 3% | 10% |
| 3% through 10% | 35% |
| Over 10% | 70% |

If the event count is 0 or less, the penalty fraction is 0. If the event count is positive and the portfolio count is 0 or less, the fraction is 70%.

## The six parts

**1. Fund vs. founders (60).** Four subsections, each kept in proportion to one minus the penalty fraction:

- Lawsuits with its own startups or founders: 30
- Pushing out founder CEOs: 12
- Down-round or pay-to-play: 10
- Blocking an acquisition or a round: 8

Then subtract 3 points for each case the fund lost or where fraud was found. That subtraction happens even when the rate is under 1%. The section cannot go below 0.

**2. Ability to support you (17.5).** The function does not turn dollars or follower counts into points. Those points are already on the input rows, and the function only adds and caps them:

- Money (fund size + reserves + whether the latest fund hit its target), capped at 6
- Media reach, capped at 6
- Help after the check (platform, intros, partner stability), capped at 5.5

Platform and intro points are expected to arrive already halved when the only source is the fund’s own claim. Each calendar year with at least one partner departure subtracts 0.5 from the stability points, and that subtraction stops at 2. An older input name, `partner_departures`, is read as a year count when `partner_departure_years` is absent.

**3. Founder experience (17.5).** Only first-hand accounts are inputs. If negative first-hand accounts are under 1% of the portfolio, the fund gets an age default:

| Age and size | Points |
|---|---|
| 10 or more years and more than 500 companies | 16.6 |
| 10 or more years | 14.9 |
| 5 or more years | 12.25 |
| 2 or more years | 8.75 |
| Otherwise, including a first fund | 7 |

If negatives are 1% or more, the tone of the accounts is used instead: mostly positive 15.75, mixed 9.6, mostly negative 3.5, a pattern of serious harm 0. A missing tone is treated as mixed. With fewer than 5 accounts, the section is the average of that tone score and the age default, rounded to two decimals. The written rules also say accounts older than 5 years count half. The function does not apply that half-weight. There is no recency input.

**4. Conflicts of interest (5).** One point is at stake per documented conflict, scaled by how many investing partners the fund has, and the section cannot go below 0. If the inputs include `scaled_deduction`, that number is the deduction (a16z records 1 for 3 conflicts across 88 partners). Otherwise each `conflict` row contributes its numeric value, or 1 when that value is 0, and the deduction is that sum divided by the partner count. With no per-conflict rows, `conflict_count` is used the same way. A one-partner firm pays the full point. No partner count means the deduction is the unscaled sum.

**5. Track record bonus (up to +3).** One point for every 5 full years of investing, and nothing if `significant_harm` is above 0. 16 years is 3. 4 years is 0. 9 years is 1.

**6. Regulatory penalty (0 to −50).** A clean record adds nothing. The function adds the numeric values already stored on the penalty rows. It does not look up the event table itself. Those stored values follow the published table: open investigation −2, charges −10, fine or settlement −10 to −20, fraud finding or a barred partner −30, a sanctioned partner or sanctioned money −50, a shareholder suit against a partner as a public-company director −0.5 to −1. The sum cannot be below −50, and a positive sum is treated as 0. Sanctions need an exact identity match. A red banner is turned on only when a penalty row is labeled `sanction` or `sanctions` and its points are −50 or worse. Counter-sanctions and crypto token-buyer class actions are written as 0 in the rules. The function will not invent that 0. It only sums what it is given.

## Formula, labels, and the a16z example

Score = section 1 + section 2 + section 3 + section 4 + bonus + penalty. The raw total is capped to 0–100, then shown to one decimal, half-up. The label uses that shown number:

| Shown score | Label |
|---|---|
| 90–100 | Very low risk |
| 75–89 | Low risk |
| 50–74 | Moderate |
| 25–49 | Elevated |
| Under 25 | High |

The published a16z worksheet is an ordinary set of inputs, not a special case in the formula. It scores 60 + 14.25 + 16.6 + 4 + 3 − 2.5 = 95.4, Very low risk, no sanctions banner. A −50 sanctions row on top of that worksheet makes the penalty −50, the shown total 47.9, and turns the banner on.

A missing input counts as 0. Two rows with the same section and name: the later row replaces the earlier one, except conflict rows and penalty rows, which are all kept.

## How this differs from scoring now

The formula file, the rules doc, and the score tests are the same bytes as on `main` today. `git diff` from `5584274` to current `main` is empty for those three paths. Firm scores are still a pure function of `score_inputs`, stored as `score_results` (version v2), with older runs kept and `is_current` marking the latest.

What the old website added, and the launch site does not, is the public `/scoring/` page (`src/scoring.html`) and its correction form (`src/js/scoring.js`). That page was removed with the rest of `src/` in pull request #179. The launch site does not recompute a score in the browser and does not call `landing_funds` or `search_funds`.
