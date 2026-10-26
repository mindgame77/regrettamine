# Gold examples for bots

Reference pages (the target look): https://regretamin.com/vc/y-combinator/ ,
https://regretamin.com/vc/a16z/ , https://regretamin.com/vc/accel/

Read with docs/DATA_RULES.md. Every item is one structured JSON object with a
`source` URL. Free text goes only in `{"note": "..."}`; `{"item": "..."}` is refused.

## People / officers
Right (y-combinator, Form ADV Schedule A):
```json
{"section":"people","name":"Garry Tan","role":"CEO/President","kind":"officer","since":"2023-01","source":"https://reports.adviserinfo.sec.gov/reports/ADV/171730/PDF/171730.pdf"}
```
Wrong (accel, before the 2026-10-26 cleanup):
```json
{"section":"people","name":"Sonali De Rycker — Member, since 04/2008 (ADV Schedule A)","role":""}
```
Why: role, date and source are jammed into `name`; `name` must be one person only. Lists like "India partners named by…: A, B, C" must be split into one item per person.

## Funds
Right (y-combinator, Form D):
```json
{"section":"funds","name":"YCP26, L.P.","amount":null,"currency":"USD","date":"2026","source":"https://www.sec.gov/Archives/edgar/data/2131753/000131586326000365/xslFormDX01/primary_doc.xml"}
```
Wrong (accel, before the 2026-10-26 cleanup):
```json
{"section":"overview","label":"Funds","value":"US adviser Schedule D: 83 private funds, including Accel VI to XVI, Growth Fund I–VII…"}
```
Why: a prose list of funds in overview. Submit one funds item per fund.

## Overview
Right (y-combinator):
```json
{"section":"overview","label":"Headquarters","value":"335 Pioneer Way, Mountain View, CA","source":"https://reports.adviserinfo.sec.gov/reports/ADV/171730/PDF/171730.pdf"}
```
Wrong (accel, before the 2026-10-26 cleanup): `{"label":"Overview","value":"Entities covered: (1) US: Accel Management Co. L.L.C, CRD 331435, … (2) …"}`.
Why: a multi-fact paragraph. One label = one short fact.

## LPs
Right shape:
```json
{"section":"lps","name":"<LP institution name>","type":"pension","source":"<public filing or LP report URL>"}
```
None of the three firms has a sourced LP list yet. Wrong: `{"section":"lps","name":"Ben Horowitz","type":"Databricks"}`. Why: that is a board seat (put it under people, `kind: "board"`), not an LP.

## Legal
Right (a16z):
```json
{"section":"legal","title":"Houghton v. AH Capital Mgmt (Compound)","date":"2022","status":"Active","allegation":false,"source":"https://www.courtlistener.com/docket/66623711/houghton-v-leshner/"}
```
Wrong (accel, removed in the 2026-10-26 cleanup): `{"section":"legal","title":"CourtListener searches run 2026-10-24 for \"Accel India\"…: 0 matching dockets"}`.
Why: a research log, not a legal item. "Nothing found" or "not searched" belongs in `{"note":...}`.

## Timeline
Right (a16z):
```json
{"section":"timeline","date":"2026-03-30","event":"Latest Form ADV filed: $106.5B regulatory AUM.","source":"https://reports.adviserinfo.sec.gov/reports/ADV/160489/PDF/160489.pdf"}
```
Also fine (a16z, informal range allowed by DATA_RULES): `{"date":"May–Jul 2025","event":"Three senior exits: O'Farrell, Pande, Wennmachers."}`.
Wrong: `{"date":"Oct 15, 2026"}` or a single date padded to `-01`.
Why: single dates must be YYYY, YYYY-MM or YYYY-MM-DD (never pad a month-only date); ranges like `May–Jul 2025` or `2024-09-24/25` may stay as-is.

## Press
Right shape:
```json
{"section":"press","outlet":"TechCrunch","date":"2026-01-09","headline":"<exact headline>","url":"<article URL>","snippet":"<one sentence quoted from it>"}
```
Wrong: a founder's tweet submitted as press. Why: first-hand founder posts go to reviews; press is outlets only.

## Reviews (what founders say)
Right (y-combinator):
```json
{"section":"reviews","who":"Naman Ambavi","quote":"My group partner called this out before we went up","date":"2026-02-03","type":"founder","source":"https://www.linkedin.com/posts/namanambavi_i-demoed-oximy-yc-w26-live-for-the-first-activity-7424266633751314433-dFZ7"}
```
Right (accel):
```json
{"section":"reviews","who":"Christian Hecker","quote":"Luca backed and believed in us early, and from the very beginning he has been a thoughtful sparring partner to me.","date":"2026-09-11","type":"founder","source":"https://tech.eu/2026/09/11/luca-bocchio-joins-balderton-as-partner-after-more-than-a-decade-in-european-vc/"}
```
Wrong (accel, Bob McGrew, before the 2026-10-26 cleanup):
```json
{"who":"Bob McGrew (Arda CEO; former OpenAI chief research officer), X, 2026-10-20","quote":"\"It's been great working with @StevoLoughlin and the @Accel team!\""}
```
Why: wrapping quotes inside `quote` (the page adds its own, so they show doubled); outlet/date meta packed into `who`; no `type`. Also wrong: two people in `who`, no author, or a funding announcement ("Excited to announce we've raised…") posted as a review.

## Deals
Right (a16z):
```json
{"section":"deals","company":"General Medicine","round":"Series B","date":"2026-10-06","amount":120000000,"currency":"USD","source":"https://www.prnewswire.com/news-releases/general-medicine-raises-120-million-to-build-the-healthcare-store-302899356.html"}
```
Wrong (a16z, before the 2026-10-26 cleanup): `{"company":"Lighter","round":"Stage tag: Venture","source":["https://a16z.com/portfolio/","https://a16z.com/companies/lunchclub/"]}`.
Why: a scraped label is not a round, and the source is another company's page. The source must name this company and this firm.

## Pre-submit checklist
1. One fact per item, structured fields filled, nothing jammed into `name`/`who`/`value`.
2. `source` is a direct URL that names this firm (and company/person); .gov only sec.gov or courts.
3. Single dates are YYYY / YYYY-MM / YYYY-MM-DD (no "Oct 15, 2026", no padding to -01); timeline ranges may stay as-is.
4. People and `who`: exactly one real person.
5. Quotes: no wrapping quote marks, no meta lines.
6. Reviews have `type`; legal has `status`.
7. Research notes, "nothing found", leads → `{"note":...}` only.
8. Check the page for an existing item first (no duplicates); flag conflicts (e.g. someone "left" but is still listed as a member).
