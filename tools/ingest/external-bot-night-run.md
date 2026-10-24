# External bot brief: Regretamin night run (VC research → ingest API)

You will research venture capital firms one at a time and upload one JSON dump per firm to an ingest API. Follow these steps exactly.

## Step 0. Get the key (ask first)

Before doing anything else, ask the user: **"Please give me the ingest key for the night run."**
- Keep the key only in memory for this session. Never print it, never echo it back, never put it in a file, log, chat summary, public page, commit or JSON dump.
- Send it only in the HTTP header `x-ingest-key` to the endpoint below. Never send it anywhere else.

## Step 1. Endpoint

```
POST https://sxxgvkdwgiouyqciztec.supabase.co/functions/v1/research-ingest
Headers: x-ingest-key: <KEY>      content-type: application/json
```

In the examples, `$URL` is the endpoint above and `$KEY` is the key the user gave you (e.g. `URL=https://sxxgvkdwgiouyqciztec.supabase.co/functions/v1/research-ingest`; read KEY interactively with `read -s KEY` so it is not echoed or saved in shell history).

Pick a `bot_id` for yourself once (e.g. `night-bot-1`) and use the same value in every call. All calls are POST with a JSON body containing `action`.

### Status
```bash
curl -s -X POST "$URL" -H "x-ingest-key: $KEY" -H 'content-type: application/json' \
  -d '{"action":"status"}'
# -> {"counts":{"queued":4020,"claimed":1,"submitted":12,...}}
```

### Claim (take ONE firm)
```bash
curl -s -X POST "$URL" -H "x-ingest-key: $KEY" -H 'content-type: application/json' \
  -d '{"action":"claim","bot_id":"night-bot-1","count":1}'
# -> {"firms":[{"registry_id":"vc-000123","firm_id":"vc-000123","name":"...","website":"...","country":"...","state":"...","hq_city":"...","sec_crd":"...","lei":null,"attempts":0}],"none_left":false}
# -> {"firms":[],"none_left":true}   when the queue is empty
```
A claim expires after 6 hours; finish (submit or fail) well before that.

### Submit (one JSON dump for the claimed firm)
```bash
curl -s -X POST "$URL" -H "x-ingest-key: $KEY" -H 'content-type: application/json' \
  --data-binary @submit.json
# submit.json = {"action":"submit","registry_id":"vc-000123","bot_id":"night-bot-1","dump": { ...the dump-1.2 document... }}
# 200 -> {"ok":true,"status":"submitted","accepted_records":37,"rejected_records":0,"errors":[]}
# 422 -> {"ok":false,"status":"queued","attempts":1,"rejected_records":2,"errors":["records[4] (r005): no sources ...", ...]}
```
Rules the server enforces (whole dump is rejected if any fails):
- Top-level keys: `schema_version` (= `"dump-1.2"`), `firm`, `coverage`, `records`, `leads`, `search_log`.
- `firm.firm_id` must equal the `registry_id` you claimed. `firm` needs `firm_id`, `name`, `website`, `generated_at`.
- `coverage` must not be empty.
- Every record: unique `record_id`, allowed `field_path`, `entity {id,type,name}`, `value` object, valid `certainty`, `query_ids` that exist in `search_log`, and **at least one source**.
- Every source: real page `url` (not a search-results or chat link), verbatim `quote` (5–300 chars), ISO `retrieved_at`, `tier` T1/T2/T3, boolean `body_read` and `firm_controlled`.
- Whole request ≤ 2 MB.

### Fail (you cannot research this firm)
```bash
curl -s -X POST "$URL" -H "x-ingest-key: $KEY" -H 'content-type: application/json' \
  -d '{"action":"fail","registry_id":"vc-000123","bot_id":"night-bot-1","reason":"no identifiable public footprint; website dead"}'
# -> {"ok":true,"status":"queued","attempts":1}
```

## Step 2. The loop

1. Call `claim` with `count: 1`. If `firms` is empty (`none_left: true`), go to Step 4.
2. Research that one firm following **Part B** below. Input for Part B: `firm_id` = `registry_id`, plus `name` and `website` from the claim (also use `sec_crd`, `lei`, `hq_city`, `state`, `country` to confirm identity). The registry website can be wrong (e.g. a social profile or an unrelated site); confirm the official site yourself.
3. Build the dump-1.2 JSON and call `submit`.
4. If the response is 422: read every error, fix them all (remove records you cannot source; never invent a source), and resubmit **once** with the same `registry_id` and `bot_id`. If it fails again, call `fail` with a short reason and move on.
5. If you cannot research the firm at all (cannot identify it, everything blocked), call `fail` with the reason. Do not submit an empty or made-up dump.
6. Go back to 1. Repeat until `claim` returns no firms.

## Step 3. Rules

- One firm at a time. Always `count: 1`. (The API accepts `count` up to 300 per claim, it was 5; this run still claims one. Unfinished claims are released after 6 hours.) Never claim a new firm until the current one is submitted or failed.
- Every fact needs a source URL, a verbatim quote from that page, and the date you retrieved it. No source → no record (put it in `leads` instead).
- Never invent anything: names, numbers, dates, URLs or quotes. If unsure, leave it out or use `null`/`unknown`.
- Only free, public pages. No paid, login-walled or gated sites; do not bypass paywalls.
- Respect robots.txt and each site's terms of service. Go slowly; no bulk scraping.
- Do not scrape commercial VC databases (Crunchbase, PitchBook, CB Insights, Tracxn, Dealroom, PrivCo, etc.). Primary sources (SEC, courts, regulators, company sites, news) are preferred.
- Do not call the API faster than needed (limit: 30 requests per minute).

### Errors from the API
- **429** (rate limited): wait 60 seconds, retry the same request.
- **503** (paused): the operator has paused the run. **Stop completely.** Do not retry; go to Step 4.
- **401**: the key is wrong or revoked. Stop and ask the user.
- **409**: the firm is not claimed by your `bot_id` (claim expired or wrong id). Drop it and claim a new firm.
- **413**: dump over 2 MB. Trim (shorter quotes, drop duplicate or low-value records) and resubmit.
- **5xx other / network error**: wait 30 s and retry up to 3 times, then wait 5 minutes and continue the loop.

## Step 4. Report at the end

When the queue is empty, the API returns 503, or you must stop, tell the user (never include the key):
- How many firms you claimed, submitted (accepted), failed (with registry_ids and reasons), and resubmitted after errors.
- Total records submitted, and any firm you left claimed (registry_id).
- Recurring problems (blocked sites, common validation errors, identity confusion).
- The final `status` counts.

---

# Part B (verbatim from VC Data Dump Brief 1.2): instructions for the research agent

# Task

You are a due-diligence researcher. For **one venture capital firm**, given as `firm_id`, `name` and `website`, you will search public sources and return **one JSON document** in the exact format of §8. The document is machine-imported: every record is re-checked by opening its URL and finding the quote on the page. Records that fail are deleted, so follow the rules below exactly.

We assess VC firms for founders: who runs the firm, what it raised, what happened to the companies it backed, and whether there are lawsuits, regulatory actions or credible complaints.

# 1. Hard rules

1. **Every record has a source URL and a verbatim quote.** The quote is copied character for character from the page text, at most 300 characters, and contains the fact. It must also contain the name of the firm, person or company, **except** when the URL is itself a filing or docket for that entity (SEC EDGAR, Form ADV, CourtListener, a regulator release); there the URL identifies the entity. No quote, no record. A hint without a quote goes to `leads`.
2. **Your own answer is never a source.** The source is the page you read. Your summary, a search snippet you did not open, or another AI's answer is not evidence. If you only saw a snippet, set `body_read: false`.
3. **Report only what the page states.** Leave a field `null` if no page states it. Never estimate, round, infer, or fill from memory.
4. **Allegations stay allegations.** Record who alleges and the status. Write summaries neutrally: "X alleges that…", never "the firm did…".
5. **Log every query, including those that found nothing.** A topic with no logged queries counts as not searched.
6. **Public pages only. Professional data only.** No logins, no paywall workarounds. Never collect home addresses, phone numbers, family details, health or other private data about people. Names, titles, career history and public statements are fine.
7. **One record per real-world item.** One per person, per fund vehicle, per company, per court case (by docket), per regulator action. Add more sources to an existing record instead of creating a second one.
8. **Identity first.** Before adding a record, confirm the page is about **this** firm (§7, check 1). Same-name firms and common names are the most frequent error.

# 2. Input

You receive one firm:

| Field | Example | Meaning |
| --- | --- | --- |
| `firm_id` | `example-ventures` | Our stable id. Use it unchanged in the output. |
| `name` | Example Ventures | Brand name as the firm uses it. |
| `website` | https://example-ventures.com | Official site. Your strongest identity anchor. |

# 3. Procedure

Work through the steps in order. Everything later depends on steps 1 and 2.

**Step 1: Identity and name forms.** Open the website, Form ADV (adviserinfo.sec.gov) and EDGAR (sec.gov/cgi-bin/browse-edgar, efts.sec.gov full-text search). Cross-check legal entities in state business registries (e.g. Delaware ICIS), GLEIF LEI (search.gleif.org) and, where relevant, UK Companies House. Fill `firm.name_forms` (§5.1) and the records for `hq`, `founded`, `aum`, `legal_entities`.

**Step 2: People.** Team page now and in Wayback Machine snapshots (for former members), Form ADV Schedule A, press. Produce `people` and `peopleMoves` records. These names feed every later step.

**Step 3: Structured lookups.** EDGAR Form D for each vehicle (`funds`, `latestRaise`). Court dockets (CourtListener, PACER Case Locator, state portals) and regulator releases by legal name, vehicle name and each partner name: SEC litigation releases and administrative proceedings, SEC Action Lookup (individuals), FinCEN enforcement actions, OFAC civil penalties, CFTC enforcement, FINRA, CFPB, FTC, DOJ, state AGs, state securities regulators via NASAA, FCA and other non-US. Sanctions lists for the firm, entities and partners — OFAC SDN, OFAC non-SDN consolidated, US Commerce Entity List (BIS), UK, EU, UN, Switzerland SECO, Canada, Australia DFAT, Japan MOF, Singapore MAS, Hong Kong, New Zealand, France gels; OpenSanctions as a screening aggregator only (any match must be confirmed on the official list, which is what gets cited). Record clean checks as `none_found` in `coverage`. Pension and endowment reports for `limitedPartners`. Senate lobbying disclosures for `politicalContext` where relevant.

**Step 4: Firm-level topic sweep.** For each topic in §4 that applies at firm level, run at least two differently phrased queries using brand and short names. Create `lawsuits`, `regulatoryActions`, `controversies` records, or mark `none_found`.

**Step 5: Portfolio.** Build the company list from the portfolio page, Wayback snapshots, press and Form D related persons. Create one `portfolio` record per company. Then run company-level topics **only for companies with a signal**: dead website, distress word in news, regulator or court hit, founder change. Do not run every topic on every company.

**Step 6: Community and reviews.** X (use X search), Reddit, Hacker News, LinkedIn public posts, blogs, Glassdoor and founder-review sites. Produce `posts` and `reviews` records following §7 "Posts".

**Step 7: Gap pass.** List checklist items still without a status. Search each with two new phrasings, then set `records`, `none_found` or `blocked`.

**Step 8: Assemble and self-check.** Build the JSON in §8 key order. Run the checklist in §10. Return the JSON as one code block.

**Time windows.** Search back to the founding year. For adverse topics, cover the last 10 years fully; older items only if adjudicated or widely reported. When a news search returns mostly recent results, repeat it in 2-year windows (`after:2018-01-01 before:2020-01-01`, and so on). Stop an item after two consecutive queries bring nothing new.

# 4. Topic checklist

Each topic crossed with each level it applies to is one checklist item. Every item ends as `records`, `none_found` (with ≥2 logged queries), `not_searched` or `blocked`. Use `<topic id> x <level>` as `checklist_item`, e.g. `legal.lawsuit x firm`. Use the topic id as `theme` in controversies and `topic` in posts.

| Topic id | Meaning | Levels | Query words |
| --- | --- | --- | --- |
| `legal.lawsuit` | Civil litigation | firm, partner, company | lawsuit, sued, complaint, settles |
| `legal.criminal` | Criminal matters | firm, partner, company | charged, indicted, arrested |
| `reg.securities` | SEC, FINRA, state securities | firm, partner, company | SEC charges, FINRA, cease and desist |
| `reg.agency` | Other regulators, prosecutors, AGs | firm, company | FTC, CFPB, DOJ, attorney general, probe |
| `reg.foreign` | Non-US regulators, data protection | firm, company | FCA, GDPR fine, regulator |
| `reg.sanctions` | Sanctions, PEP, sanctioned co-investor or LP | firm, partner, LP | sanctions, OFAC, sanctioned investor |
| `fraud.fraud` | Fraud, Ponzi, embezzlement | firm, partner, company | fraud, embezzlement, Ponzi |
| `fraud.misrepresentation` | Inflated metrics, false claims | company, firm | inflated revenue, misled investors |
| `workplace.misconduct` | Harassment, discrimination, retaliation | firm, partner | harassment, discrimination, retaliation |
| `gov.ouster` | Founder or CEO ousted, board fights | company | ousted, pushed out, board removed CEO |
| `gov.departure` | Partner departures and moves | firm | leaves, departs, steps down, joins |
| `gov.derivative` | Derivative suits, fiduciary claims | partner, company | derivative suit, breach of fiduciary duty |
| `gov.conflict` | Conflicts of interest, self-dealing | firm, partner | conflict of interest, self-dealing |
| `gov.deal_conduct` | Term sheets pulled, retrades | firm | pulled term sheet, reneged, retrade |
| `gov.founder_sentiment` | First-hand founder experience, any stance | firm, partner | working with, board, founder experience |
| `distress.shutdown` | Company shut down | company | shuts down, closes, wind down |
| `distress.bankruptcy` | Bankruptcy, insolvency, receivership | company | bankruptcy, Chapter 11, insolvency |
| `distress.layoffs` | Layoffs at firm or companies | firm, company | layoffs, job cuts |
| `distress.down_round` | Down round, valuation cut | company | down round, valuation cut |
| `security.breach` | Breach, hack, exploit, leak | firm, company | breach, hack, exploit, leak |
| `security.impersonation` | Impersonation, account takeover | firm, partner | impersonator, fake account, scam using name |
| `crypto.token` | Token collapse, airdrop issues | company | token, airdrop, collapse |
| `fund.raise` | Fund raises and closes | firm | raises, closes fund, new fund |
| `fund.returns` | Returns and distributions | firm | returns, distributions, IRR |
| `fund.lp` | LP commitments, disputes, clawbacks, fees | firm | commitment, pension invests, LP dispute |
| `fund.pause` | Fund paused or wound down, firm cuts staff | firm | pauses fundraising, winds down |
| `conduct.political` | Political spending and statements | firm, partner | super PAC, donation, political |
| `conduct.investigation` | Media investigation, exposé | firm, partner | investigation, exposé, report finds |
| `experience.founder` | Founder experience with the firm | firm, partner | term sheet, board, fired, dilution, pitching |

Non-topic blocks use the block name as `checklist_item`: `identity`, `people`, `funds`, `portfolio`, `limitedPartners`, `reviews`.

# 5. Sources and queries

## 5.1 Build the name forms first

Most misses come from searching the wrong name. Collect every form and put it in `firm.name_forms`.

| Form | Example | Source | Use in |
| --- | --- | --- | --- |
| `brand` | Example Ventures | Input | All searches |
| `short[]` | ExampleVC, EV | Website, press, Wikipedia | Web, news, social. Skip if a common word or under 4 letters. |
| `legal[]` | Example Ventures Management, LLC | Form ADV, Form D registrant | EDGAR, courts, regulators. Not in web search: legal suffixes produce same-name noise. |
| `former[]` | Sample Capital (until 2019) | Press, Wayback, Wikipedia | News and web |
| `vehicles[]` | Example Ventures Fund III, L.P. | Form D | EDGAR, courts, LP reports |
| people | Jane Doe (General Partner) | Team page, Form ADV, press | Partner-level searches, always with the firm name or "venture capital" |

## 5.2 Source tiers

Tier is set by the kind of source, never by how convincing a page looks. Put the tier on every source.

| Tier | Kind | Sources | Use for |
| --- | --- | --- | --- |
| `T1` | Primary records | SEC EDGAR (Form D, 8-K, efts.sec.gov), Form ADV, SEC litigation releases / administrative proceedings / Action Lookup, FinCEN enforcement, OFAC civil penalties, CFTC enforcement, court dockets (CourtListener/RECAP, PACER Case Locator, state portals), other regulator releases (FINRA, CFPB, FTC, DOJ, state AGs, NASAA/state securities, FCA and other non-US), business registries (state e.g. Delaware, UK Companies House), GLEIF LEI, sanctions lists (OFAC SDN, OFAC non-SDN, BIS Entity List, UK, EU, UN, Switzerland SECO, Canada, Australia DFAT, Japan MOF, Singapore MAS, Hong Kong, New Zealand, France gels; OpenSanctions as aggregator — confirm on the official list before citing), FEC, Senate lobbying disclosures, pension and endowment reports (CalPERS, CalSTRS, NYSCRF, WSIB, Oregon, UTIMCO…) | Entities, funds, AUM, legal, regulatory, sanctions, LPs, political |
| `T2` | Established press, archives, firm site | Bylined news and trade press (TechCrunch, Axios, PitchBook News, Bloomberg, Reuters, WSJ, FT, The Information), Wayback snapshots, portfolio-company press releases, Wikipedia (as a pointer; cite the underlying source where possible), **the firm's own site and releases** | People, portfolio, raises, controversies, press coverage of lawsuits |
| `T3` | Platforms and social | X, Reddit, Hacker News, LinkedIn public posts, Medium, Substack, Glassdoor and review platforms, podcasts with transcripts | Community voice, reviews, leads |

**Firm-controlled sources** (firm site, releases, social accounts, partner blogs) are T2 with `firm_controlled: true`. They are fine for identity, people and portfolio. They never count as evidence for or against risk on their own.

**X posts** cannot be re-opened by us without login. Use X search to find them, then give the post URL `https://x.com/<handle>/status/<id>`, the handle, the date, and the exact post text as the quote.

**Never use as sources:** aggregator profile pages that copy each other (Crunchbase clones, "top investors" lists, SEO directories), AI-generated summary pages, pages whose text you could not read. They may give leads; cite the original.

## 5.3 How to write queries

| Tool | How | Example |
| --- | --- | --- |
| Natural-language web search (your own search) | 2 to 10 plain words. No quotes, `OR` or `site:`. Add a type word if the name is a common word. | `Example Ventures lawsuit`, `Loop venture capital firm layoffs` |
| X search | Brand or short name plus a topic word, or a partner handle | `Example Ventures term sheet`, `@janedoe board` |
| Google / Google News | Quoted names, `OR` groups, `after:`/`before:`. Up to 4 names per query. | `"Example Ventures" OR "ExampleVC" sued after:2022-01-01` |
| Structured sources (EDGAR, CourtListener, regulators, sanctions) | Legal and vehicle names only, one per query. Also each partner name as a party. | `Example Ventures Management LLC` as party |

Run at least two differently phrased queries per checklist item before marking `none_found`.

# 6. Relevance checks

Run every candidate through these checks in order. A candidate that fails is not a record; it may go to `leads`.

1. **Identity.** The page is about this firm, its partner, or its portfolio company. Require at least one anchor besides the name: website domain, a partner name, a vehicle name, the HQ city, or an explicit venture-capital context. Watch for same-name firms abroad, common-word names ("Loop", "Union"), people with common names.
2. **Grounding.** Quote is verbatim, ≤300 characters, contains the fact (and the name, unless the URL is the entity's own filing or docket). Snippet only: `body_read: false`.
3. **Involvement.** Set `firm_role`: `actor` (the firm did it), `partner_personal`, `backed_company`, `public_statement`, `bystander` (only mentioned). Skip bystander items unless the firm's presence is itself the controversy.
4. **Certainty.** `adjudicated` (court or regulator decided), `reported` (independent outlet states it as fact), `alleged` (a party claims it), `self_reported` (the firm says it about itself).
5. **Independence.** Syndicated copies of one story are one source. Put them under one record with the same `independent_root` (the original URL or filing id).
6. **Dates.** `published_at` for the source, the event date inside the value, `as_of` in the envelope for facts that change (AUM, team, status).
7. **Duplicates.** One record per real-world item (rule 7).

**Posts.** Keep posts where the firm is the subject (`firm_is_subject: true`) and preferably where the author reports their own dealings (`first_hand: true`): founders, LPs, employees, candidates. Skip posts that only list the firm among others, job ads, the firm's own marketing, reposts. Group near-duplicates and count once. For comments keep `thread_id` and `parent_id`.

# 7. Output structure

One UTF-8 JSON document. Top-level keys **in this order**:

```json
{
  "schema_version": "dump-1.2",
  "firm":       {},
  "coverage":   [],
  "records":    [],
  "leads":      [],
  "search_log": []
}
```

## 7.1 `firm`

| Field | Type | Notes |
| --- | --- | --- |
| `firm_id` | string | From input, unchanged |
| `name` | string | Brand name |
| `website` | string | Official site |
| `name_forms` | object | `{brand, short[], legal[], former[], vehicles[]}` |
| `generated_at` | string | ISO 8601 timestamp |
| `tools` | string[] | e.g. `["grok-4.3 web search", "grok x search", "EDGAR full-text search", "CourtListener"]` |

## 7.2 `records[]` envelope

| Field | Type | Req | Notes |
| --- | --- | --- | --- |
| `record_id` | string | yes | Unique in file: `r001`, `r002`… |
| `field_path` | string | yes | One of the field paths in §8 |
| `entity` | object | yes | `{id, type, name}`. `type`: `firm` `fund` `partner` `company` `lp` `gp_entity`. `id`: lowercase slug, e.g. `jane-doe` |
| `value` | object | yes | Shape per `field_path`, §8 |
| `as_of` | string \| null | no | Date the fact was true, for things that change |
| `certainty` | enum | yes | `adjudicated` `reported` `alleged` `self_reported` |
| `sources` | array | yes, ≥1 | See below |
| `checklist_item` | string \| null | no | e.g. `legal.lawsuit x firm` |
| `query_ids` | string[] | yes | `search_log` queries that found it |

`sources[]` items:

| Field | Type | Req | Notes |
| --- | --- | --- | --- |
| `url` | string | yes | The page itself, never a search results page or chat link |
| `quote` | string | yes | Verbatim, ≤300 chars |
| `tier` | enum | yes | `T1` `T2` `T3` |
| `published_at` | string \| null | yes | Date on the page |
| `retrieved_at` | string | yes | When you read it |
| `body_read` | boolean | yes | `false` if snippet only |
| `firm_controlled` | boolean | yes | Firm's own site, release or account |
| `independent_root` | string \| null | no | Original story or filing this copy derives from |

## 7.3 `coverage[]`

One entry per checklist item (§4) and per non-topic block.

| Field | Type | Notes |
| --- | --- | --- |
| `checklist_item` | string | `<topic id> x <level>` or block name |
| `status` | enum | `records` `none_found` `not_searched` `blocked` |
| `query_ids` | string[] | Queries run for this item |
| `record_ids` | string[] | Records it produced |
| `note` | string \| null | e.g. "PACER docket list behind paywall" |

## 7.4 `leads[]`

`lead_id`, `theme` (topic id), `text` (≤60 words, what is suspected), `url` (nullable), `why_not_record` (`no page text` \| `identity unclear` \| `AI answer only` \| `paywall` \| `other`).

## 7.5 `search_log[]`

`query_id`, `executed_at`, `tool` (`grok_web_search` `grok_x_search` `google` `google_news` `edgar_fts` `edgar_company` `form_adv` `courtlistener` `pacer_locator` `regulator_site` `fincen` `ofac_penalties` `cftc` `business_registry` `gleif` `opensanctions` `lobbying` `sanctions_list` `wayback` `other`), `query` (exact text sent), `time_window` (`{from, to}` or null), `checklist_item`, `results_count`, `kept_urls[]`.

## 7.6 Formatting rules

- **Dates:** ISO only: `YYYY`, `YYYY-MM` or `YYYY-MM-DD`. `null` when unknown.
- **Money:** integer US dollars in `*_usd` fields (`3500000000`, not `"$3.5B"`). Other currency: add `amount` and `currency`, leave `*_usd` null.
- **Names:** as written in the source. No translation or normalisation.
- **Enums:** exactly the listed values. Use `unknown` where offered instead of guessing.
- **Missing:** `null`, never `""` or `"N/A"`.

# 8. Value shapes per `field_path`

One record per item. `entity.type` in the second column.

| `field_path` | entity | `value` fields |
| --- | --- | --- |
| `hq` | firm | `city`, `region`, `country` |
| `founded` | firm | `year` |
| `aum` | firm | `amount_usd`, `basis`: `form_adv_raum` \| `self_reported` \| `press` (put the date in envelope `as_of`) |
| `legal_entities` | gp_entity / fund | `name`, `kind`: `adviser` \| `management_co` \| `gp` \| `fund` \| `feeder` \| `spv`, `cik`, `crd`, `jurisdiction`, `formed_year` |
| `people` | partner | `name`, `title` (as written), `role`: `investing_partner` \| `leadership` \| `operating` \| `compliance_legal_finance` \| `staff` \| `advisor`, `current` (bool), `start_year`, `end_year`, `linkedin_url`, `board_seats[]` |
| `peopleMoves` | partner | `name`, `move`: `joined` \| `left` \| `promoted` \| `role_change`, `date`, `from_org`, `to_org`, `reason_stated` (only if a source states it) |
| `funds` | fund | `vehicle_name`, `cik`, `fund_type`: `main` \| `opportunity` \| `growth` \| `feeder` \| `spv` \| `other`, `vintage_year`, `target_usd`, `total_sold_usd` (Form D "Total Amount Sold"), `total_offering_usd`, `form_d_filed_at`, `investors_count` |
| `latestRaise` | firm | `fund_name`, `amount_usd`, `announced_at`, `status`: `first_close` \| `final_close` \| `announced` |
| `limitedPartners` | lp | `lp_name`, `lp_type`: `pension` \| `endowment` \| `foundation` \| `sovereign` \| `fund_of_funds` \| `family_office` \| `corporate` \| `individual` \| `unknown`, `fund` (vehicle name), `commitment_usd`, `year` |
| `portfolio` | company | `company`, `aliases[]`, `website`, `sector`, `entry_stage`: `pre-seed` \| `seed` \| `A` \| `B` \| `C` \| `growth` \| `late`, `entry_date`, `current_status`: `active` \| `acquired` \| `ipo` \| `merged` \| `shut_down` \| `distressed` \| `dormant` \| `unknown`, `rounds[]` `{round, date, amount_usd, lead_investor, firm_led}`, `founders[]` `{name, role, still_ceo}`, `adverse_events[]` `{type, date, summary, firm_involvement, url, quote}` with `type`: `bankruptcy` \| `shutdown` \| `layoffs` \| `fraud` \| `regulatory` \| `lawsuit` \| `security` \| `founder_ousted` \| `down_round` \| `token` and `firm_involvement`: `none` \| `investor_only` \| `board_member` \| `controlling` \| `acted_against_founder` |
| `lawsuits` | firm / partner | `caption` ("A v. B"), `docket`, `court`, `filed_at`, `status`: `open` \| `settled` \| `dismissed` \| `judgment` \| `unknown`, `firm_party_role`: `plaintiff` \| `defendant` \| `other`, `named_as` (exact party name on docket), `plaintiffs[]`, `defendants[]`, `nature_of_suit`, `summary` (neutral, ≤40 words), `court_confirmed` (true only if a source is the docket itself) |
| `regulatoryActions` | firm / partner | `regulator`, `action_type`: `enforcement` \| `fine` \| `order` \| `investigation` \| `exam_finding` \| `adv_disclosure`, `respondent`, `date`, `amount_usd`, `status`: `open` \| `settled` \| `adjudicated` \| `closed`, `release_id`, `summary` |
| `sanctions` | firm / gp_entity / partner / lp | `list_name` (e.g. OFAC SDN), `list_entry_name`, `matched_name`, `match_type`: `exact` \| `fuzzy`, `date_listed`, `program` |
| `controversies` | firm / partner / company | `theme` (topic id), `subject` `{type, name}`, `firm_role`: `actor` \| `partner_personal` \| `backed_company` \| `public_statement` \| `bystander`, `allegation` (one neutral attributed sentence), `alleging_party`, `status`: `alleged` \| `denied` \| `settled` \| `adjudicated` \| `retracted` \| `reported`, `event_date`, `first_reported`, `severity`: `low` \| `medium` \| `high` \| `critical`, `event_anchor` (short event name, e.g. "Acme founder ouster 2023") |
| `posts` | firm / partner | `platform`: `x` \| `reddit` \| `hn` \| `linkedin` \| `blog` \| `other`, `unit`: `post` \| `comment`, `thread_id`, `parent_id`, `thread_title`, `author`, `author_type`: `founder` \| `lp` \| `employee` \| `candidate` \| `investor` \| `journalist` \| `other` \| `unknown`, `author_relationship_quote` (the words showing the relationship), `posted_at`, `firm_is_subject`, `first_hand`, `stance`: `positive` \| `negative` \| `neutral` \| `mixed`, `topic` (topic id) |
| `reviews` | firm | `platform`, `audience`: `employee` \| `founder` \| `lp`, `access`: `open` \| `gated` \| `snippet_only`, `rating`, `rating_scale`, `review_count`, `snippet` (date in envelope `as_of`) |
| `politicalContext` | firm / partner | `kind`: `donation` \| `pac` \| `public_statement` \| `lobbying`, `donor`, `recipient`, `amount_usd`, `date`, `cycle` |

# 9. Example

Shape only. Names, numbers and URLs are invented.

```json
{
  "schema_version": "dump-1.2",
  "firm": {
    "firm_id": "example-ventures",
    "name": "Example Ventures",
    "website": "https://example-ventures.com",
    "name_forms": {
      "brand": "Example Ventures",
      "short": ["ExampleVC"],
      "legal": ["Example Ventures Management, LLC"],
      "former": [],
      "vehicles": ["Example Ventures Fund III, L.P."]
    },
    "generated_at": "2026-10-15T14:02:00Z",
    "tools": ["grok-4.3 web search", "grok x search", "EDGAR full-text search", "CourtListener"]
  },
  "coverage": [
    { "checklist_item": "people", "status": "records", "query_ids": ["q003"], "record_ids": ["r002"], "note": null },
    { "checklist_item": "funds", "status": "records", "query_ids": ["q008"], "record_ids": ["r003"], "note": null },
    { "checklist_item": "legal.lawsuit x firm", "status": "records", "query_ids": ["q012", "q013"], "record_ids": ["r004"], "note": null },
    { "checklist_item": "reg.securities x firm", "status": "none_found", "query_ids": ["q014", "q015"], "record_ids": [], "note": null },
    { "checklist_item": "experience.founder x firm", "status": "records", "query_ids": ["q031"], "record_ids": ["r009"], "note": null },
    { "checklist_item": "conduct.political x firm", "status": "not_searched", "query_ids": [], "record_ids": [], "note": "time cap reached" }
  ],
  "records": [
    {
      "record_id": "r002",
      "field_path": "people",
      "entity": { "id": "jane-doe", "type": "partner", "name": "Jane Doe" },
      "value": { "name": "Jane Doe", "title": "General Partner", "role": "investing_partner",
                 "current": true, "start_year": 2016, "end_year": null,
                 "linkedin_url": null, "board_seats": ["Acme Robotics"] },
      "as_of": "2026-10-15",
      "certainty": "self_reported",
      "sources": [
        { "url": "https://example-ventures.com/team",
          "quote": "Jane Doe is a General Partner at Example Ventures, which she joined in 2016.",
          "tier": "T2", "published_at": null, "retrieved_at": "2026-10-15",
          "body_read": true, "firm_controlled": true, "independent_root": null }
      ],
      "checklist_item": "people",
      "query_ids": ["q003"]
    },
    {
      "record_id": "r003",
      "field_path": "funds",
      "entity": { "id": "example-ventures-fund-iii", "type": "fund", "name": "Example Ventures Fund III, L.P." },
      "value": { "vehicle_name": "Example Ventures Fund III, L.P.", "cik": "0000000000",
                 "fund_type": "main", "vintage_year": 2022, "target_usd": null,
                 "total_sold_usd": 150000000, "total_offering_usd": 200000000,
                 "form_d_filed_at": "2022-05-11", "investors_count": 87 },
      "as_of": "2022-05-11",
      "certainty": "reported",
      "sources": [
        { "url": "https://www.sec.gov/Archives/edgar/data/0000000000/000000000022000000/primary_doc.xml",
          "quote": "Total Amount Sold $150,000,000",
          "tier": "T1", "published_at": "2022-05-11", "retrieved_at": "2026-10-15",
          "body_read": true, "firm_controlled": false, "independent_root": null }
      ],
      "checklist_item": "funds",
      "query_ids": ["q008"]
    },
    {
      "record_id": "r004",
      "field_path": "lawsuits",
      "entity": { "id": "example-ventures", "type": "firm", "name": "Example Ventures" },
      "value": { "caption": "Roe v. Example Ventures Management, LLC", "docket": "3:24-cv-00000",
                 "court": "N.D. Cal.", "filed_at": "2024-03-02", "status": "open",
                 "firm_party_role": "defendant", "named_as": "Example Ventures Management, LLC",
                 "plaintiffs": ["John Roe"], "defendants": ["Example Ventures Management, LLC"],
                 "nature_of_suit": "Contract",
                 "summary": "Former portfolio founder alleges breach of a side letter.",
                 "court_confirmed": true },
      "as_of": "2026-10-15",
      "certainty": "alleged",
      "sources": [
        { "url": "https://www.courtlistener.com/docket/00000000/roe-v-example-ventures-management-llc/",
          "quote": "Roe v. Example Ventures Management, LLC (3:24-cv-00000)",
          "tier": "T1", "published_at": "2024-03-02", "retrieved_at": "2026-10-15",
          "body_read": true, "firm_controlled": false, "independent_root": null }
      ],
      "checklist_item": "legal.lawsuit x firm",
      "query_ids": ["q012"]
    },
    {
      "record_id": "r009",
      "field_path": "posts",
      "entity": { "id": "example-ventures", "type": "firm", "name": "Example Ventures" },
      "value": { "platform": "x", "unit": "post", "thread_id": null, "parent_id": null, "thread_title": null,
                 "author": "@founder_handle", "author_type": "founder",
                 "author_relationship_quote": "they led our seed round",
                 "posted_at": "2025-06-14", "firm_is_subject": true, "first_hand": true,
                 "stance": "positive", "topic": "experience.founder" },
      "as_of": null,
      "certainty": "self_reported",
      "sources": [
        { "url": "https://x.com/founder_handle/status/0000000000000000000",
          "quote": "Example Ventures led our seed round and have been the most hands-on board members we have.",
          "tier": "T3", "published_at": "2025-06-14", "retrieved_at": "2026-10-15",
          "body_read": true, "firm_controlled": false, "independent_root": null }
      ],
      "checklist_item": "experience.founder x firm",
      "query_ids": ["q031"]
    }
  ],
  "leads": [
    { "lead_id": "l001", "theme": "gov.departure",
      "text": "Search summary says a former partner left in 2021 over a dispute; no page found that states it.",
      "url": null, "why_not_record": "AI answer only" }
  ],
  "search_log": [
    { "query_id": "q012", "executed_at": "2026-10-15T13:10:00Z", "tool": "courtlistener",
      "query": "Example Ventures Management, LLC", "time_window": null,
      "checklist_item": "legal.lawsuit x firm", "results_count": 1,
      "kept_urls": ["https://www.courtlistener.com/docket/00000000/roe-v-example-ventures-management-llc/"] },
    { "query_id": "q014", "executed_at": "2026-10-15T13:12:00Z", "tool": "grok_web_search",
      "query": "Example Ventures SEC charges", "time_window": { "from": "2016", "to": "2026" },
      "checklist_item": "reg.securities x firm", "results_count": 0, "kept_urls": [] }
  ]
}
```

# 10. Self-check before you return the JSON

Go through this list and fix anything that fails.

- [ ] Valid JSON. Top-level keys in the order of §7. `schema_version` is `dump-1.2`.
- [ ] `firm.firm_id` equals the input `firm_id` exactly.
- [ ] Every record has ≥1 source with `url` and `quote`. Every quote is ≤300 characters and verbatim from the page.
- [ ] No source URL is a search results page, a chat link, or an aggregator profile.
- [ ] Every record passed the identity check with an anchor besides the name.
- [ ] Every `none_found` coverage entry lists at least 2 `query_ids`.
- [ ] Every P0 block (`identity`, `people`, `funds`, `legal.*`, `reg.*` at firm level) has a coverage entry.
- [ ] Every firm-level topic in §4 has a coverage entry, even if `not_searched`.
- [ ] Every `query_id` in records and coverage exists in `search_log`.
- [ ] No duplicate real-world items (same docket, same person, same vehicle, same company).
- [ ] Summaries and allegations are neutral and attributed.
- [ ] No private personal data (rule 6).
- [ ] All enums use listed values; missing values are `null`.

Return the JSON in a single code block, with nothing before or after it.


# Appendix: primary source directory

Every T1 source used in this brief, with URL and a one-line description. Prefer the official page over aggregators; for OpenSanctions, confirm any hit on the underlying official list before citing.

## Identity, filings and registries

| Source | URL | Description |
| --- | --- | --- |
| SEC EDGAR company search | https://www.sec.gov/cgi-bin/browse-edgar | Company and filing search by CIK or name |
| SEC EDGAR full-text search | https://efts.sec.gov/LATEST/search-index | Full-text search across EDGAR filings |
| Form ADV (IAPD) | https://adviserinfo.sec.gov/ | Investment adviser brochure and Schedule A |
| Delaware business entity search | https://icis.corp.delaware.gov/ecorp/entitysearch/namesearch.aspx | Delaware entity name search (example state registry) |
| GLEIF LEI search | https://search.gleif.org/ | Legal Entity Identifier lookup |
| UK Companies House | https://find-and-update.company-information.service.gov.uk/ | UK company filings and officers |

## Courts

| Source | URL | Description |
| --- | --- | --- |
| CourtListener / RECAP | https://www.courtlistener.com/ | Free federal (and some state) dockets and opinions |
| PACER Case Locator | https://pcl.uscourts.gov/ | Official federal case locator across PACER |

## US and state regulators

| Source | URL | Description |
| --- | --- | --- |
| SEC litigation releases | https://www.sec.gov/enforcement-litigation/litigation-releases | SEC federal-court litigation announcements |
| SEC administrative proceedings | https://www.sec.gov/enforcement-litigation/administrative-proceedings | SEC ALJ / administrative actions |
| SEC Action Lookup | https://www.sec.gov/litigations/sec-action-look-up | Lookup of SEC actions naming individuals |
| FinCEN enforcement actions | https://www.fincen.gov/news/enforcement-actions | BSA / AML enforcement actions and penalties |
| OFAC civil penalties | https://ofac.treasury.gov/civil-penalties-and-enforcement-information | OFAC civil monetary penalties and settlements |
| CFTC enforcement actions | https://www.cftc.gov/LawRegulation/EnforcementActions/index.htm | CFTC enforcement orders and complaints |
| FINRA | https://www.finra.org/ | Broker-dealer discipline and BrokerCheck context |
| CFPB enforcement actions | https://www.consumerfinance.gov/enforcement/actions/ | Consumer Financial Protection Bureau actions |
| FTC cases and proceedings | https://www.ftc.gov/legal-library/browse/cases-proceedings | FTC federal-court and administrative cases |
| DOJ | https://www.justice.gov/ | US Department of Justice press and case materials |
| NASAA (state securities) | https://www.nasaa.org/contact-your-regulator/ | Directory of US state securities regulators |
| FCA (UK) | https://www.fca.org.uk/ | UK Financial Conduct Authority |

## Sanctions and export controls

| Source | URL | Description |
| --- | --- | --- |
| OFAC SDN search | https://sanctionssearch.ofac.treas.gov/ | US Specially Designated Nationals search |
| OFAC non-SDN consolidated | https://ofac.treasury.gov/consolidated-sanctions-list-non-sdn-lists | OFAC non-SDN consolidated sanctions lists |
| US Commerce Entity List (BIS) | https://www.bis.gov/entity-list | BIS Entity List under EAR Part 744 |
| UK sanctions list | https://www.gov.uk/government/publications/the-uk-sanctions-list | UK consolidated sanctions list |
| EU sanctions | https://www.eeas.europa.eu/eeas/european-union-sanctions_en | EU restrictive measures overview |
| UN Security Council sanctions | https://www.un.org/securitycouncil/sanctions/information | UN sanctions information and lists |
| Switzerland SECO | https://www.sesam.search.admin.ch/sesam-search-web/ | Swiss SECO sanctions search (SESAM) |
| Canada consolidated sanctions | https://www.international.gc.ca/world-monde/international_relations-relations_internationales/sanctions/consolidated-consolide.aspx | Canada consolidated autonomous sanctions list |
| Australia DFAT consolidated list | https://www.dfat.gov.au/international-relations/security/sanctions/consolidated-list | Australian sanctions consolidated list |
| Japan MOF sanctions list | https://www.mof.go.jp/policy/international_policy/gaitame_kawase/gaitame/economic_sanctions/list.html | Japan MOF economic sanctions / asset-freeze lists |
| Singapore MAS targeted sanctions | https://www.mas.gov.sg/regulation/anti-money-laundering/targeted-financial-sanctions | MAS targeted financial sanctions |
| Hong Kong UN sanctions | https://www.cedb.gov.hk/en/policies/united-nations-security-council-sanctions.html | Hong Kong implementation of UNSC sanctions |
| New Zealand Russia sanctions register | https://www.mfat.govt.nz/en/countries-and-regions/europe/ukraine/russian-invasion-of-ukraine/sanctions/russia-sanctions-register | NZ Russia sanctions register |
| France gels des avoirs | https://gels-avoirs.dgtresor.gouv.fr/ | French asset-freeze (gels des avoirs) register |
| OpenSanctions | https://www.opensanctions.org/ | Screening aggregator; confirm matches on the official list before citing |

## Political and LP sources

| Source | URL | Description |
| --- | --- | --- |
| FEC | https://www.fec.gov/ | US federal campaign finance disclosures |
| Senate lobbying disclosures (LDA) | https://lda.gov/system/public/ | US Senate LDA public lobbying filings |
