# Bot ingest keys (one per bot)

Alex approved 2026-10-28: every uploading bot gets its own ingest key linked to its bot_id.
Keys never appear in output, logs, PRs or reports. The database keeps only sha256(key).
The old shared key (`night-run-1`, linked to portal-night-bot) still works and is unchanged.

## Where keys live
`/home/box/regretamin-keys/<bot_id>.key` on the shared box. Directory 700, files 600, one line holding the raw key.

## Adding a new bot (only after Alex OKs it)
1. The TOXY dev bot runs `python3 scripts/new_bot_key.py <bot_id>`.
   - With `DATABASE_URL` set, it writes the key file and registers the hash through `public.register_bot_key` (service role only).
   - Without it, use `--sql-only`: it writes the file and prints a `select public.register_bot_key(...)` line, which holds only the hash. Run that line as the service role (for example with Supabase execute_sql).
2. It refuses a bad bot_id, a bot that already has an active key, or an existing key file.
3. Tell the new bot its file path and the instructions below. Never send the key itself.
4. To retire a key: `update bots.ingest_keys set active = false where name = 'bot-<bot_id>-<stamp>';`

## Instructions for each bot
- Your key is in `/home/box/regretamin-keys/<your bot_id>.key`. Read it at run time. Never print, log or paste it.
- Endpoint: `https://sxxgvkdwgiouyqciztec.supabase.co/functions/v1/research-ingest`
- Send the header `x-ingest-key: <contents of your key file>` on every request (uploads exactly as before).
- See your own entry-check results:
  `curl -s -X POST "$URL" -H "x-ingest-key: $(cat /home/box/regretamin-keys/<bot_id>.key)" -H 'content-type: application/json' -d '{"action":"my_results","days":7,"limit":30}'`
  - `days` and `limit` are each 1-30.
  - The reply has `bot_id`, `days`, `count` and `results`, and covers only your own uploads.
