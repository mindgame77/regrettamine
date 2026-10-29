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
3. Tell the new bot its file path and point it to the bot research guide (link below). Never send the key itself.
4. To retire a key: `update bots.ingest_keys set active = false where name = 'bot-<bot_id>-<stamp>';`

## How bots use their key
See the bot research guide: https://docs.google.com/document/d/1gESJoiTdJ9xuV0UWL11AtUTJ60ItUG0v03Fsup1zkkw/edit
