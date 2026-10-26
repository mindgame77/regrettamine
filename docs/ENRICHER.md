# Enricher (toxy-enricher) ingest

Endpoint: `POST https://sxxgvkdwgiouyqciztec.supabase.co/functions/v1/research-ingest`
Headers: `x-ingest-key: <contents of /workspace/keys/toxy-enricher-ingest-key.txt>`, `content-type: application/json`

Body:
```json
{"action": "enrich", "bot_id": "toxy-enricher",
 "enrichment": {"slug": "accel", "registry_id": "vc-000082", "submission_id": 197,
   "sections": {"Overview": [{"label": "Headquarters", "value": "Palo Alto, CA", "source": "https://..."}],
                "People & board seats": [{"name": "Jane Roe", "role": "General Partner", "kind": "officer", "since": "2019", "source": "https://..."},
                                         {"name": "Jane Roe", "role": "Director", "kind": "board", "company": "Acme Inc", "source": "https://..."},
                                         {"note": "Schedule A lists 14 individuals; 2 confirmed"}],
                "Funds": [{"name": "Accel XV", "amount": "650000000", "currency": "USD", "date": "2023", "source": "https://..."}],
                "Limited partners": [{"name": "Yale University", "type": "endowment", "source": "https://..."}],
                "Legal & regulatory": [{"title": "Doe v. Accel", "date": "2024-05", "status": "pending", "source": "https://..."}],
                "Timeline": [{"date": "2021", "event": "Opened London office", "source": "https://..."}],
                "Press coverage": [{"outlet": "...", "date": "YYYY-MM-DD", "headline": "...", "url": "https://...", "snippet": "..."}],
                "What founders say": [{"who": "...", "quote": "...", "source": "https://..."}]},
   "confirm": [], "fix": [{"field": "people[Name].current", "bot_value": "...", "correct_value": "...", "source_url": "https://..."}],
   "add": [{"field": "people", "value": {"name": "...", "role": "..."}, "source_url": "https://..."}],
   "leads": [{"field": "lawsuits", "value": {"title": "..."}, "source_url": "https://..."}],
   "owned_media": [{"url": "https://www.seedtoscale.com", "label": "SeedToScale (Accel podcast)"}, "https://www.youtube.com/@accel"],
   "notes": "...",
   "searches": [{"section": "board_seats", "site": "sec.gov", "query": "...", "searched_at": "2026-10-24T10:00:00-07:00", "result": "found|none|blocked|error", "item_count": 0},
                {"section": "checks", "site": "trade.gov", "query": "Kevin Zhang", "searched_at": "2026-10-24T17:13:00-07:00", "result": "none", "item_count": 0, "name_only": true, "list": "ITAR Debarred (DTC)", "check": 3}]}}
```

**Data rules (docs/DATA_RULES.md):** one structured item per fact with the fields shown above; free text only as
`{"note": "..."}` (kept, never published). `{"item": "..."}` free text is refused. Duplicates of page rows add their source;
a different role/figure is flagged as a conflict, not overwritten. Every verdict is stored in `publish_checks`.

Rules: every item needs a source URL; .gov/.mil are rejected except sec.gov and courts (courtlistener, uscourts, PACER);
AUM must contain a number; leads/allegations are shown as "Lead" / Unverified; founder quotes from the firm's own accounts are labelled not independent.
Own media: a founder or press item is the firm's own media (`independent=false`, outlet text gets "· Own media") when its URL is on the
firm's domain or social handles, or on an entry of the per-firm `firm_owned_media` list (a podcast, YouTube channel, newsletter or blog the
firm runs). Send `owned_media` (URLs, or `{url, label}`; a path such as `/@handle` limits the match to that channel). Entries from the
latest enrichment replace earlier enricher entries; manual entries (e.g. Accel's seedtoscale.com) stay.
Fixes never edit the friend's rows: they go to `firm_corrections` and override what the page shows. A people fix targets the named person's row (friend or enricher row); with no match it is rejected (the correction is stored, not shown). Resubmitting a firm replaces the previous enrichment.
Name-only sanctions: a same-name hit that is not a confirmed identity is not a finding. Keep `result` as `none` (searches still allow only `found`, `none`, `blocked`, `error`) and set `name_only` true, `list` to the list name, and `check` to 1–10 (`3` for ITAR / export / debarment). The check shows as Clear with the line "A person with the same name appears on {list}; we couldn't confirm it's the same person." Do not put that hit in a section as a legal item. A surname-only line, or a "name-only near match" with no list, is not this flag. Older notes that say `name-only match:` and name the list are still read. The stored payload is not rewritten.

The reply lists accepted/rejected items with a reason, `notes_kept`, `outcomes` (published/merged/conflict/rejected counts) and `conflicts`, plus `bot_feedback`.

Views (service role): `firm_section_status`, `firm_site_coverage`, `site_search_stats` (all read `search_log_current`: rows with no enrichment_id or from the latest valid enrichment per firm+bot; older rows stay in `search_log`), `feedback_pattern_stats`; RPC `next_firms_to_enrich(p_limit)`.
