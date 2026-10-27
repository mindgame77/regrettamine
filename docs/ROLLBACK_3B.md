Step 3b abandoned 2026-10-26 ~11 PM PT; never went live. Reason: Supabase-owned functions (net, auth, cron, storage...) stay executable by PUBLIC and can't be revoked without superuser; secrets can't be set from here.

# Rollback for the ingest login (step 3b)

Recorded from the live function before this change was merged.

| | |
|---|---|
| Function | `research-ingest` |
| id | `ae7b5892-f954-4635-bc77-7ad65aeabe55` |
| version | 28 |
| verify_jwt | false |
| bundle hash (`ezbr_sha256`) | `e0c800e9e4fc0411dd3875aacce6e72cb45ff982e30700352cb48801a8dca607` |
| source commit | `21d722d28cb32a9052f62968e666654183d730ea` |
| source file | `supabase/functions/research-ingest/index.ts` |
| source sha256 | `6433c8f5b722732d7e7f520f7b87d98f8694ce6d8f9e19d6029a955cb28f963b` |

That file uses `SUPABASE_SERVICE_ROLE_KEY` through `createClient`. It does not read `BOT_INGEST_DB_URL`.

Do not print a password, a database URL, or a key while rolling back.

## Put the old door back

1. Redeploy `research-ingest` from that commit, with `verify_jwt` false. Use the file as it is in git. Do not edit it and do not deploy any other function.

```
git show 21d722d28cb32a9052f62968e666654183d730ea:supabase/functions/research-ingest/index.ts
```

The service key is already injected into the function. The old source reads it. A new version number is normal. The deployed file must match the source sha256 above.

2. The database role can stay. It has no table grants. To stop password logins without dropping it:

```
alter role bot_ingest nologin;
```

Turn it back on later with `alter role bot_ingest login`. Do not drop the role and do not revoke the migration as part of this rollback.

3. Optional. Remove the URL secret so other functions no longer have it in their environment. The old door does not read it. The service key stays injected either way.

```
supabase secrets unset BOT_INGEST_DB_URL --project-ref sxxgvkdwgiouyqciztec
```

## Check

POST to the function with no `x-ingest-key` and no `Authorization` header. Expect 401 and `unauthorized`. Do not send a keyed upload. The deployed source must contain `SUPABASE_SERVICE_ROLE_KEY` and must not read `BOT_INGEST_DB_URL`.
