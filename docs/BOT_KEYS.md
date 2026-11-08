# Bot ingest keys (one per bot)

Alex approved 2026-10-28: every uploading bot gets its own ingest key linked to its bot_id.
Keys never appear in output, logs, PRs or reports. The database keeps only sha256(key), except a pickup copy that is deleted when the bot takes it.
The old shared key (`night-run-1`, linked to portal-night-bot) still works and is unchanged. Pickup does not enroll it.

## Where keys live
`/home/box/regretamin-keys/<bot_id>.key` on the shared box. Directory 700, files 600, one line holding the raw key.

## Adding a new bot (only after Alex OKs it)
1. The TOXY dev bot runs `python3 scripts/new_bot_key.py <bot_id>`.
   - With `DATABASE_URL` set, it writes the key file, registers the hash through `public.register_bot_key` (service role only), and seals that same key for pickup when the pickup function is installed.
   - Without it, use `--sql-only`: it writes the file and prints a `select public.register_bot_key(...)` line, which holds only the hash. Run that line as the service role. Do not paste the raw key into SQL. After pickup is installed, run `python3 scripts/new_bot_key.py <bot_id> --seal` on the machine that has the file.
2. It refuses a bad bot_id, a bot that already has an active key, or an existing key file. `--seal` does not make a second key and does not change the hash.
3. A bot that does not share the box uses pickup below. Do not send the key, the proof, or the file path.
4. To retire a key: `update bots.ingest_keys set active = false where name = 'bot-<bot_id>-<stamp>';`

## Pickup
Not live until this migration is applied and the `bot-key-apply` function is deployed. Until then, do not send the address to a bot.

The address has no secret in it:

`POST https://sxxgvkdwgiouyqciztec.supabase.co/functions/v1/bot-key-apply`

Header: `content-type: application/json`. No ingest key yet. No service role key.

Owner, once:
1. The bot already has one active key. If create did not seal it, run `python3 scripts/new_bot_key.py <bot_id> --seal` on the machine that has the file. That does not print the key.
2. Send the bot the address and its bot_id.
3. The bot applies and tells you `proof_prefix` (8 characters). That prefix is not the key and not the proof.
4. In the SQL editor, run `select public.pending_bot_key_pickups();`. If that bot is pending and the prefix matches, run `select public.approve_bot_key_pickup('<bot_id>');` once.
5. If the prefix does not match, run `select public.clear_bot_key_pickup('<bot_id>');` and let the bot apply again. Do not approve a row you did not just ask for.

The first apply locks that bot_id until you approve or clear it. A one-time link is not used. A token in the address would be an admission secret, and it would leak wherever the address was copied.

Bot:
1. Make a random proof of at least 32 characters. Save it privately. Do not put it in chat, a URL, or a header.
2. Post `{"bot_id":"<bot_id>","proof":"<proof>"}` to the address.
3. While the reply is `{"ok":true,"status":"pending","proof_prefix":"<8 chars>"}`, wait and send the same body again. Tell the owner the prefix only.
4. The one reply `{"ok":true,"status":"delivered","key":"..."}` is the research key. Save it privately (file mode 600 if you write a file). Delete the proof. Never print the key.
5. If that reply never arrives, stop. The owner runs `--seal` on the same file and approves the new apply. The key is not rotated.
6. Send the saved key only in the header `x-ingest-key` to `https://sxxgvkdwgiouyqciztec.supabase.co/functions/v1/research-ingest-v2`.
7. Claim one existing firm, submit, then done. See the bot research guide. Do not call `add_firm`. The key is a normal research key, so `add_firm` would still work; this bot does not use it. Rate limits, freeze, and the ingest pause switch are unchanged.

Waiting bots. Both keys are already registered. Seal the existing file. Do not register them again.
- Conductor: bot_id `external-research-bot-1`, key id `41196041-eafb-400d-9b7a-0eeda350f73a`
- PortalOne: bot_id `external-portal-one-bot`, key id `15ac08c7-9c9f-4c1b-9397-d759d8eb8f00`

`portal-night-bot` (`night-run-1`) is not part of pickup.

## How bots use their key
See the bot research guide: https://docs.google.com/document/d/1gESJoiTdJ9xuV0UWL11AtUTJ60ItUG0v03Fsup1zkkw/edit
