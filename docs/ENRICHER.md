# Enricher (toxy-enricher) ingest

Endpoint: `POST https://sxxgvkdwgiouyqciztec.supabase.co/functions/v1/research-ingest`
Headers: `x-ingest-key: <contents of /workspace/keys/toxy-enricher-ingest-key.txt>`, `content-type: application/json`

Body:
```json
{"action": "enrich", "bot_id": "toxy-enricher",
 "enrichment": {"slug": "accel", "registry_id": "vc-000082", "submission_id": 197,
   "sections": {"Overview": [{"item": "...", "source": "https://..."}],
                "Legal & regulatory": [...], "People & board seats": [...], "Funds": [...], "Timeline": [{"date": "2021", "item": "...", "source": "..."}],
                "Press coverage": [{"outlet": "...", "date": "YYYY-MM-DD", "headline": "...", "url": "https://...", "snippet": "..."}],
                "What founders say": [{"who": "...", "quote": "...", "source": "https://..."}]},
   "confirm": [], "fix": [{"field": "people[Name].current", "bot_value": "...", "correct_value": "...", "source_url": "https://..."}],
   "add": [{"field": "...", "value": "...", "source_url": "https://..."}],
   "leads": [{"field": "...", "value": "...", "source_url": "https://..."}],
   "notes": "...",
   "searches": [{"section": "board_seats", "site": "sec.gov", "query": "...", "searched_at": "2026-10-24T10:00:00-07:00", "result": "found|none|blocked|error", "item_count": 0}]}}
```

Rules: every item needs a source URL; .gov/.mil are rejected except sec.gov and courts (courtlistener, uscourts, PACER);
AUM must contain a number; leads/allegations are shown as "Lead" / Unverified; founder quotes from the firm's own accounts are labelled not independent.
Fixes never edit the friend's rows: they go to `firm_corrections` and override what the page shows. Resubmitting a firm replaces the previous enrichment.
The reply lists accepted/rejected items with a reason, plus `bot_feedback`.

Views (service role): `firm_section_status`, `firm_site_coverage`, `site_search_stats`, `feedback_pattern_stats`; RPC `next_firms_to_enrich(p_limit)`.
