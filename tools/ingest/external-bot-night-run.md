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
  -d '{"action":"submit","items":[{"firm_id":41,"box":"F28","table":"v2_news_items","fact":{"source_url":"https://example.com/story","source_level":"2","source_date":"2026-11-01","source_type":"news"}}]}'
```

Each fact is `{firm_id, box, table, fact:{source_url, source_level, source_date, source_type, ...}}`. The other fact fields are the columns for that table in section F.

### 3. Failed facts

The reply lists every item. A failed fact has a reason, for example `Rejected: no source link (source_url)`. Fix that fact and resend only the corrected ones. Do not resend facts that were accepted.

## Errors

- **401**: the key is wrong or revoked. Stop and ask the user.
- **403**: the key is frozen. Stop and report the reason.
- **429**: wait 60 seconds, then retry the same request.
- **503**: ingest is paused. Stop completely. Do not retry.
