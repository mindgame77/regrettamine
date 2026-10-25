# On-demand research (paid lane)

A visitor clicks **Check with 1 credit** on a firm page that still needs research: an unchecked ("Not checked yet") page,
or a published partial page where any of the 10 checks still says *Not checked yet*. The credit is spent with the usual rules
(signed out: free checks, 4 free spends per IP per 30 days; signed in: free then paid credits), the page unlocks for that
visitor, and the firm goes to the front of the research queue in the **paid lane**.

## Data (migration `20261024240000_ondemand_research.sql`)

| Object | What it holds |
| --- | --- |
| `research_queue.lane` (`normal` / `paid` / `request`), `research_queue.paid_at` | Paid lane flag and when it was first paid for. |
| `ondemand_jobs` | One open job per firm (`queued` / `in_progress`, then `done` / `refunded`), `missing_checks` = `[{n, title}]` still *Not checked yet*. |
| `research_requests` | One row per requester per job: `user_id` or `anon_id`, optional `email` (signed in: account email; signed out: the page's email box), `status`, `spend_kind`. |
| `check_events.kind = 'refund_ondemand'` | Credit given back (+1) when a job was not done within 24 h. A refund takes the unlock back. |
| view `ondemand_queue` | The paid lane in claim order (admin / service role only). |

Several people paying for the same firm share one job; each gets their own request (and email).

## Who moves the queue

* Paid request (`unlock_firm` -> `_ondemand_enqueue`): paid lane, front of the queue. The email is saved whenever one
  is available (the account email, or the address typed in the pay popup / notify box), including when the firm is
  already fully checked. A finished firm does not go back on the paid lane; the address is stored on a done request so
  the ready email can go out.
* Notify me (`notify_when_checked`) and the request-a-check form (`request_check`): a firm already on the site gets a
  paid-lane job (`spend_kind = 'request'`, no credit, never refunded), the same shape as a hand-routed notify. A name
  that is not on the site gets `research_queue.registry_id = 'req-<check_requests id>'` (or `req-c<id>` when `req-<id>`
  is already a firm request) in lane `request`. See docs/FIRM_REQUESTS.md for that lane.
* Page views (people or crawlers) never reorder anything (`bump_firm_check` no longer changes priority; the page no longer calls it).

## Bot: `toxy-researcher-3` (Regretamin Researcher 3)

Researcher 3 handles **requested firms only**: paid checks (lane `paid`) and "Request this firm" requests for firms not
on the site yet (lane `request`, see docs/FIRM_REQUESTS.md). Only `bot_id = "toxy-researcher-3"` claims those two lanes,
every other bot_id only gets `normal`-lane firms, and Researcher 3 never gets normal-lane work. Use the same
research-ingest endpoint and ingest key as the other researchers.

Claim size: other bots can claim up to 300 normal-lane firms per `claim` call (`count` 1-300, default 1; it was 5). The paid lane still hands out one paid firm per call. Claims use skip-locked, so two bots never get the same firm, and unfinished claims go back to the queue after 6 hours.

`POST https://sxxgvkdwgiouyqciztec.supabase.co/functions/v1/research-ingest`
headers `x-ingest-key: <ingest key>`, `content-type: application/json`

1. **Claim** (one firm per call; `count` is ignored for this bot). Order: (1) paid checks (open job with a credit spend),
   (2) other paid-lane jobs (firm requests linked to a firm already on the site), (3) new-firm requests (lane `request`); oldest first in each:
   ```json
   {"action": "claim", "bot_id": "toxy-researcher-3"}
   ```
   Response: `{"firms": [{registry_id, firm_id, name, website, country, state, hq_city, sec_crd, lei, attempts,
   "paid": true, "ondemand_job_id": 12, "missing_checks": [{"n": 8, "title": "..."}], "requesters": 2,
   "requested_at": "...", "refund_at": "..."}], "none_left": false}`.
   Paid firms carry `"paid": true`. A new-firm request has `registry_id` `req-<request id>` and no paid fields (no page yet;
   the page is made when the research lands). `none_left: true` = no requested firm waiting; poll again later (e.g. every
   minute). Do not claim normal-lane work with this bot_id.
2. **Research** the firm. On a partial firm, focus on `missing_checks`, but submit the whole dump as usual.
3. **Submit** exactly like the other researchers (same validation, same `research_submit`):
   ```json
   {"action": "submit", "bot_id": "toxy-researcher-3", "registry_id": "<claimed registry_id>", "dump": { ... }}
   ```
   A valid submission runs the usual `ensure_firm_for_registry` path (page created / upgraded), then trigger
   `zz_ondemand_done` marks the job and all its requests `done` and moves the firm back to the normal lane.
   `zz_stamp_firm_report` copies `payload.firm.generated_at` onto `firms.report_date` (when that date is empty or
   older) and sets `firms.updated_at`, which is the sitemap lastmod. The submission payload is not modified.
   The dump has no list score, and nothing on the page computes `firms.list_score` from the checks.
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
* `ondemand-notify` sends via Resend (`RESEND_API_KEY`), **plain text, from
  `Regretamin <support@regretamin.com>`** (all transactional mail, also `notify-checks`). Links use `https://regretamin.com/`
  (`SITE_URL` constant). Kinds: `ready` (a check is done, including a notify-me signup on a firm already on the site),
  `ready_request` (only a "Request this firm" row, `firm_request_id` set; docs/FIRM_REQUESTS.md), `refund`, `received`.
  Only live firm pages (published, real, not test, not deleted) get a ready/refund email. Each is emailed once
  (`notified_at`; a failed send is kept in `notify_error` and not retried automatically). `TEST_ONLY_TO` is not a send
  gate: a leftover value used to skip every other address without setting `notified_at` or `notify_error`, so the tick
  retried the skip forever. Email only, never SMS.
* A notify-me signup that is already linked to a job (`check_requests.research_request_id`) is not mailed again. The
  research request is the only ready email. `ready_check_requests` (the older worker) skips linked signups.
