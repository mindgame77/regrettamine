# Toxy Score v2: Scoring Rules

Version 2, agreed Oct 2, 2026. The score runs from 0 to 100, and higher is better. It never goes below 0 or above 100.

The score measures **how the fund itself treats founders**. It does not measure how many of its portfolio companies ran into trouble on their own.

## Core principles
1. **Every fund starts with full points** in each section and loses points only for real, verified evidence about its own behavior.
2. **Rates, not counts.** Bad events are measured as a share of all the companies the fund has backed. **Under 1% is not significant and costs nothing.**
3. **Only verified sources count.** A source must have a working link, name the fund in the text, and show the fund's role (plaintiff or defendant). Content farms, copycat names (for example the "ai16z" token), and claims backed only by anonymous sources are excluded.
4. **Fund role matters.** A lawsuit the fund brought is not the same as one brought against it. Suits against a partner only in their role as a director of a public company are minor.
5. **Coverage is shown separately.** Missing data lowers the coverage %, never the reliability of the score itself. We show "Sources: X% reliable" and "Coverage: Y% checked" side by side.

## Rate scale (used by every section)
| Share of the portfolio affected | Effect |
|---|---|
| Under 1% | No penalty |
| 1–3% | Small penalty (about 10% of the section's points) |
| 3–10% | Medium penalty (about 35%) |
| Over 10% | Large penalty (about 70% or more) |

## Sections

### 1. Fund vs. founders and portfolio companies (60 points)
| Sub-part | Points | What it counts |
|---|---|---|
| Lawsuits with its own startups or founders | 30 | Cases between the fund and its own companies, founders or executives, scored by the rate scale |
| Pushing out founder CEOs | 12 | Removals the fund drove, scored by the rate scale |
| Down-round or pay-to-play behavior | 10 | Punitive terms, aggressive cram-downs |
| Blocking acquisitions or funding rounds | 8 | Documented vetoes or blocking |

Extra deduction: −3 per case where the fund lost or fraud was found, applied even below 1%.

### 2. Ability to support you (17.5 points)
| Sub-part | Points | What it counts |
|---|---|---|
| Money | 6 | Recent fund size, money left to invest, whether the latest fund hit its target |
| Media reach (capped) | 6 | Social posts about its companies, a YouTube channel, a podcast, its own media |
| Help after the check | 5.5 | Platform team, recruiting help, customer intros, partner stability |

Claims the fund makes about itself count at half until founders confirm them. Partner departures cost −0.5 each, up to −2.

### 3. Founder experience (17.5 points)
Only first-hand accounts count, from a founder or a named ex-executive. Anonymous gossip does not count.

**When there are no significant negatives** (negative accounts are under 1% of the portfolio, or there are none), the fund gets its age default:
| Fund age | Default |
|---|---|
| 10+ years and over 500 companies | 95% (16.6) |
| 10+ years | 85% (14.9) |
| 5–10 years | 70% (12.25) |
| 2–5 years | 50% (8.75) |
| Under 2 years or a first fund | 40% (7) |

**When there is significant feedback** (1% or more of the portfolio), we score the content:
| Overall tone | Score |
|---|---|
| Mostly positive | 90% (15.75) |
| Mixed | 55% (9.6) |
| Mostly negative | 20% (3.5) |
| A pattern of serious harm (founders pushed out, fraud) | 0 |

- **Small samples:** with fewer than 5 accounts, the score is the average of the content score and the age default.
- **Recency:** accounts from the last 5 years count fully, and older ones count half.

### 4. Conflicts of interest (5 points)
This covers partners on the boards of competing companies, backing a founder's direct competitor, and in-house companies that compete with portfolio companies.
- −1 per documented conflict, **scaled by partner count**. A conflict involving 1 of 88 investing partners counts less than one involving the fund's only partner.
- The section can't go below 0.

### 5. Track record bonus (up to +3)
+1 for every 5 years of investing with no significant pattern of harm, up to +3.

### 6. Regulatory, sanctions and SEC penalty (0 to −50)
A clean record is normal and earns 0. This section can only take points away.
| Event | Penalty |
|---|---|
| Open investigation, no charges | −2 |
| Charges filed | −10 |
| Fine or settlement | −10 to −20 (depends on size and whether investors or founders were harmed) |
| Fraud finding, or a partner barred by a regulator | −30 |
| Sanctioned partner, or money from a sanctioned country or person | **−50 plus a red warning banner** |
| Shareholder suit against a partner as a public-company director | −0.5 to −1 |

- Sanctions require an **exact identity match** (date of birth, nationality, ID), never a name-only match.
- **Counter-sanctions** imposed by sanctioned countries (for example Russia or Iran listing a former US official) cost 0.
- Class actions by crypto token buyers are not fund-vs-founder. They appear for context only and cost 0.

## Formula
Score = Section 1 + Section 2 + Section 3 + Section 4 + Track record bonus − Regulatory penalty, capped between 0 and 100.

## Bands
| Score | Label |
|---|---|
| 90–100 | Very low risk |
| 75–89 | Low risk |
| 50–74 | Moderate |
| 25–49 | Elevated |
| Under 25 | High |

Any sanctions finding shows a red banner, whatever the score.

## Worked example: Andreessen Horowitz (a16z)
| Section | Max | Given | Why |
|---|---|---|---|
| 1. Fund vs. founders | 60 | 60 | Run The World and Zenefits are 0.07% each of about 1,456 companies, under 1%. Neither was a loss or a fraud finding. |
| 2. Ability to support you | 17.5 | 14.25 | Money 5 ($15B raised Jan 2026, reserves not public). Media 6 (about 290K YouTube subscribers, a podcast, its own media team, about 1.08M followers on X). Help 3.25 (the fund's own claims at half, 2025 partner departures). |
| 3. Founder experience | 17.5 | 16.6 | 2 negative first-hand accounts are 0.14%, under 1%. Default for 10+ years and over 500 companies. |
| 4. Conflicts | 5 | 4 | Board seats at competitors (Databricks, Fivetran), the incubation clause in its SEC filing, and the Uniswap vote, scaled across 88 investing partners. |
| 5. Track record bonus | +3 | +3 | 16 years of investing |
| 6. Regulatory penalty | 0 to −50 | −2.5 | DOJ board-seat probe −2 (no charges). Coinbase director suit −0.5. |
| **Total** | | **95.4, Very low risk** | Coverage about 39% |
