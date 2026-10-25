# On-demand research (paid lane)

A visitor clicks **Check with 1 credit** on a firm page that still needs research: an unchecked ("Not checked yet") page,
or a published partial page where any of the 10 checks still says *Not checked yet*. Signed out or signed in, that
button opens the unlock popup and does not spend. The popup title is the firm name. **Check this firm** spends one
credit when the visitor has one (free, then paid; 4 free spends per IP per 30 days) and does not ask for an email.
With no credit left, the same button starts single-credit checkout. **See plans** opens the existing pricing popup.
**Already have an account? Sign in** opens the existing sign-in popup, and is hidden once they are signed in.
The page unlocks for that visitor. A slower locked `firm_page` response cannot redraw the lock over an unlock that
already landed.

The email field is only for a firm that still needs research, and only while signed out. It is optional, labeled
**Email me when it's ready**. An address that is filled in is saved on the paid-lane job so the ready email can go
out. Leaving it blank still spends the credit and starts the research. A firm whose 10 checks are already done has
no email field. Signed in, the popup has no email field; the account address is saved when research starts.

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

* Paid request (`unlock_firm` -> `_ondemand_enqueue`): paid lane, front of the queue. The email is saved when one
  is available (the account email, or the optional address on an unresearched firm). A blank address still starts
  the research. A finished firm does not go back on the paid lane, and a spend with no address stores nothing extra.
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

A paid or request job takes a firm that a normal-lane claim is holding, including a gap-fill claim (`last_error` `gap-fill claim`, for example `portal-night-bot`). `_preempt_normal_claims()` runs when the job is filed and again at the start of every `research_claim`. It sets that row back to `queued` on the paid or request lane, clears `claimed_by` / `claimed_at`, and stores the previous bot in `prior_claimed_by`. Researcher 3 can claim it on the next call. A normal claim with no paid or request job is not touched; it still lasts 6 hours. Researcher 3's own claim is not released this way.

The firm page shows **Checking** only while `firm_page` / `firm_check_status` report the queue as `claimed`. A normal-lane claim older than 6 hours with no open paid or request job is reported as `queued`, with no started time, so the page shows **Not checked yet**. The queue row stays claimed until the next `research_claim` releases it. A page view does not release it. A paid or request claim still shows Checking after 6 hours. While Checking is showing, the line is `Started {when}` with `{when}` from `launch/js/dates.js` (for example `Started Oct 24, 2026, 3:58 PM PT`).

The previous bot's later upload is still accepted. `research_submit` from `prior_claimed_by` inserts the payload as sent. If nobody else holds the firm, a valid submit follows the usual path (`submitted`, and `zz_ondemand_done` closes the open job). If Researcher 3 already holds the claim, the dump is still stored and the usual ingest triggers run, and that claim stays so Researcher 3 can submit too. An invalid dump from the preempted bot is stored and does not burn attempts or drop the paid claim. Raw submission and enrichment payloads are not rewritten.

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

* Page: requesters see **Research in progress** (existing banner, on the summary page and on `/full/`) and, on the summary
  page, the existing *Email me when it's ready* box until a bot holds the claim (then the usual *Checking* view). That
  banner is the confirmation after **Check this firm**. They keep the full page after it is done (the credit is the unlock).
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
