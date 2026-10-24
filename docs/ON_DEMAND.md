# On-demand research (paid lane)

A visitor clicks **Check with 1 credit** on a firm page that still needs research: an unchecked ("Not checked yet") page,
or a published partial page where any of the 10 checks still says *Not checked yet*. The credit is spent with the usual rules
(signed out: free checks, 4 free spends per IP per 30 days; signed in: free then paid credits), the page unlocks for that
visitor, and the firm goes to the front of the research queue in the **paid lane**.

## Data (migration `20261024240000_ondemand_research.sql`)

| Object | What it holds |
| --- | --- |
| `research_queue.lane` (`normal` / `paid`), `research_queue.paid_at` | Paid lane flag and when it was first paid for. |
| `ondemand_jobs` | One open job per firm (`queued` / `in_progress`, then `done` / `refunded`), `missing_checks` = `[{n, title}]` still *Not checked yet*. |
| `research_requests` | One row per requester per job: `user_id` or `anon_id`, optional `email` (signed in: account email; signed out: the page's email box), `status`, `spend_kind`. |
| `check_events.kind = 'refund_ondemand'` | Credit given back (+1) when a job was not done within 24 h. A refund takes the unlock back. |
| view `ondemand_queue` | The paid lane in claim order (admin / service role only). |

Several people paying for the same firm share one job; each gets their own request (and email).

## Who moves the queue

* Paid request (`unlock_firm` -> `_ondemand_enqueue`): paid lane, front of the queue.
* Request-a-check form (`request_check`): when the text names a known firm exactly (name, display name, short name, slug or
  alias), the firm moves to the front of the **normal** lane.
* Page views (people or crawlers) never reorder anything (`bump_firm_check` no longer changes priority; the page no longer calls it).

## Bot: `toxy-researcher-3` (Regretamin Researcher 3)

Only `bot_id = "toxy-researcher-3"` claims paid jobs, and every other bot_id never gets a paid-lane firm. Use the same
research-ingest endpoint and ingest key as the other researchers.

Claim size: other bots can claim up to 300 normal-lane firms per `claim` call (`count` 1-300, default 1; it was 5). The paid lane still hands out one paid firm per call. Claims use skip-locked, so two bots never get the same firm, and unfinished claims go back to the queue after 6 hours.

`POST https://sxxgvkdwgiouyqciztec.supabase.co/functions/v1/research-ingest`
headers `x-ingest-key: <ingest key>`, `content-type: application/json`

1. **Claim** (one firm at a time, oldest paid first; `count` is ignored for this bot):
   ```json
   {"action": "claim", "bot_id": "toxy-researcher-3"}
   ```
   Response: `{"firms": [{registry_id, firm_id, name, website, country, state, hq_city, sec_crd, lei, attempts,
   "paid": true, "ondemand_job_id": 12, "missing_checks": [{"n": 8, "title": "..."}], "requesters": 2,
   "requested_at": "...", "refund_at": "..."}], "none_left": false}`.
   `none_left: true` = no paid job waiting; poll again later (e.g. every minute). Do not claim normal-lane work with this bot_id.
2. **Research** the firm. On a partial firm, focus on `missing_checks`, but submit the whole dump as usual.
3. **Submit** exactly like the other researchers (same validation, same `research_submit`):
   ```json
   {"action": "submit", "bot_id": "toxy-researcher-3", "registry_id": "<claimed registry_id>", "dump": { ... }}
   ```
   A valid submission runs the usual `ensure_firm_for_registry` path (page created / upgraded), then trigger
   `zz_ondemand_done` marks the job and all its requests `done` and moves the firm back to the normal lane.
   Invalid (422): fix all errors and resubmit once, same registry_id and bot_id.
4. **Can't finish**: `{"action": "fail", ...}` / `{"action": "skip", ...}` as usual. A claim older than 6 h is released back
   to the paid lane. Anything not done 24 h after the first request is refunded automatically.

Then claim the next one.

## Status, emails, refunds

* Page: requesters see **Research in progress** (existing banner style) and the existing *Email me when it's ready* box until a
  bot holds the claim (then the usual *Checking* view). They keep the full page after it is done (the credit is the unlock).
* `ondemand_tick()` runs every 2 minutes (pg_cron job `regretamin-ondemand-tick`): `ondemand_refund_expired()` refunds
  requests older than 24 h (credit back to the same bucket, `refund_ondemand` event), then, when `ondemand_outbox()` has mail,
  calls Edge Function `ondemand-notify` (pg_net). The call is authenticated with the Vault secret `ondemand_cron_key`.
* `ondemand-notify` sends via Resend (`RESEND_API_KEY`; optional `TEST_ONLY_TO`), **plain text, from
  `Regretamin <support@regretamin.com>`** (all transactional mail, also `notify-checks`). Links use `https://regretamin.com/`
  (`SITE_URL` constant). Kinds: `ready`, `ready_request` (firm requests, docs/FIRM_REQUESTS.md), `refund`, `received`.
  Only live firm pages (published, real, not test, not deleted) get a ready/refund email. Each is emailed once
  (`notified_at`; a failed send is kept in `notify_error` and not retried automatically). Email only, never SMS.
