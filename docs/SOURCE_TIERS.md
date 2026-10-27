# Source tiers

Every source URL is tagged by `source_tier(url)`:
* **trusted**: the host is in `trusted_source_domains` (or a subdomain of one). Regulators (SEC, FINRA), courts
  (CourtListener, uscourts, PACER), registers (GLEIF, Companies House), elections (fec.gov), sanctions (OFAC /
  sanctionssearch.ofac.treas.gov, treasury.gov, the UK sanctions list, sanctionsmap.eu, UN Security Council), government
  (gov.uk incl. the FCDO pages) and other government domains.
* **other**: any other http(s) page. Accepted and shown, labelled as another source.
* **null / not a source**: missing, not http(s), or a search/chat result page (Google/Bing/DuckDuckGo search, Grok, ChatGPT, Perplexity).

## needs_source
A fact or record with no usable source is **kept** (raw bot data is never changed), flagged `needs_source`, **hidden on
public pages**, and queued for the Regretamin Enricher:
* view `facts_needing_source` (service role); research-ingest `{"action": "needs_source"}`.
* add a source: `fact_add_source(...)` / research-ingest `{"action": "add_source", "submission_id", "record_id", "url"}`.
  Once it has a source, the fact shows.

## research-ingest
Submissions are no longer rejected for non-allowlisted sources. Each record is tagged; the response has
`tiers: {trusted, other, needs_source}`. `{"action": "sources"}` returns the allowlist.
Change the allowlist with a migration (insert into `trusted_source_domains`).
