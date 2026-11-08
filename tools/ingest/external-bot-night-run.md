# External bot brief: v2 research door

The only rulebook is [docs/PAGE_DATA_GUIDE.md](../../docs/PAGE_DATA_GUIDE.md). What to collect is section F. This brief is how to call the v2 door. It is not a second set of data rules.

Do not send a v1 dump to `research-ingest`. Do not publish a page yourself.

## Step 0. Get the key (ask first)

Before doing anything else, ask the user: **"Please give me the ingest key for the night run."**
- Keep the key only in memory for this session. Never print it, never echo it back, never put it in a file, log, chat summary, public page, commit or JSON body.
- Send it only in the HTTP header `x-ingest-key` to the endpoint below. Never send it anywhere else.

## Step 1. Endpoint

```
POST https://sxxgvkdwgiouyqciztec.supabase.co/functions/v1/research-ingest-v2
Headers: x-ingest-key: <KEY>      content-type: application/json
```

`$URL` is that endpoint. `$KEY` is the key the user gave you. Read it with `read -s KEY` so it is not echoed or saved in shell history.

Three calls, in this order.

### 1. add_firm

```bash
curl -s -X POST "$URL" -H "x-ingest-key: $KEY" -H 'content-type: application/json' \
  -d '{"action":"add_firm","firm":{"name":"Example Ventures","website":"https://example-ventures.com","registry_id":"vc-000123"}}'
# -> {"ok":true,"firm_id":41,"created":true,"slug":"example-ventures"}
# same registry_id or slug again -> the same firm_id, "created":false
```

This inserts one `v2_firms` row, or returns the firm that already matches that registry id or slug. It does not publish facts.

### 2. Submit facts

One item per fact. `firm_id` is the number from add_firm.

```bash
curl -s -X POST "$URL" -H "x-ingest-key: $KEY" -H 'content-type: application/json' \
  -d '{"action":"submit","items":[{"firm_id":41,"box":"F5","table":"v2_investor_principles","fact":{"investor_name":"Example Person","investor_title":"General Partner","summary":"Looks for founders who know the customer.","quote":"We back founders who know the customer.","published_at":"2026-01-15","source_url":"https://example.com/quote","source_level":"2","source_date":"2026-11-01","source_type":"Firm website"}}]}'
```

Do not send `v2_lp_commitments` or `v2_news_items`.

Each fact is `{firm_id, box, table, fact:{source_url, source_level, source_date, source_type, ...}}`. The other fact fields are the columns for that table in section F.

A new row stays hidden until the Checker passes it. Do not send display name, page slug, firm status, or founder feedback. One example for each door that was closed. The investor quote is an exact excerpt, 150 characters or less.

```json
{"firm_id":41,"box":"F5","table":"v2_investor_principles","fact":{"investor_name":"Example Person","investor_title":"General Partner","summary":"Looks for founders who know the customer.","quote":"We back founders who know the customer.","published_at":"2026-01-15","source_url":"https://example.com/quote","source_level":"2","source_date":"2026-11-01","source_type":"Firm website"}}
{"firm_id":41,"box":"F2","table":"v2_firm_stages","fact":{"stage":"Seed","source_text":"We lead seed rounds.","source_url":"https://example.com/focus","source_level":"2","source_date":"2026-11-01","source_type":"Firm website"}}
{"firm_id":41,"box":"F2","table":"v2_firm_industries","fact":{"industry_text":"Developer tools","position":1,"source_url":"https://example.com/focus","source_level":"2","source_date":"2026-11-01","source_type":"Firm website"}}
{"firm_id":41,"box":"F1","table":"v2_firm_types_firms","fact":{"firm_type":"VC","source_url":"https://example.com/about","source_level":"2","source_date":"2026-11-01","source_type":"Firm website"}}
{"firm_id":41,"box":"F8","table":"firm_fund_announcements","fact":{"name":"Example Fund","amount_usd":100000000,"display":"$100M","announced_on":"2026-01-15","source_url":"https://example.com/fund","source_level":"2","source_date":"2026-11-01","source_type":"Firm website"}}
{"firm_id":41,"box":"F2","table":"v2_firm_check_sizes","fact":{"program_name":"Seed","amount_text":"$500K to $2M","min_usd":500000,"max_usd":2000000,"source_url":"https://example.com/seed","source_level":"2","source_date":"2026-11-01","source_type":"Firm website"}}
{"firm_id":41,"box":"F1","table":"v2_firm_former_names","fact":{"name":"Example Old Name","until_year":2010,"source_url":"https://example.com/about","source_level":"2","source_date":"2026-11-01","source_type":"Firm website"}}
```

### 3. Failed facts

The reply lists every item. A failed fact has a reason, for example `Rejected: no source link (source_url)`. Fix that fact and resend only the corrected ones. Do not resend facts that were accepted.

## Errors

- **401**: the key is wrong or revoked. Stop and ask the user.
- **403**: the key is frozen. Stop and report the reason.
- **429**: wait 60 seconds, then retry the same request.
- **503**: ingest is paused. Stop completely. Do not retry.
