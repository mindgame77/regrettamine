> Dated record, not the rulebook. The only rules are in [docs/PAGE_DATA_GUIDE.md](PAGE_DATA_GUIDE.md). Where this file disagrees with that guide, the guide wins.

# Request this firm

When a search finds nothing, the dropdown says **No results. Request this firm →** and opens `/pending/?q=<name>`.
The visitor leaves an email and, optionally, the firm's website. It's free.

## Storage
* `firm_requests`: one row per firm, deduped by normalized name (`name_key = _queue_name_key(name)`, the same key
  research_queue uses). Website domain kept in `website_domain`. Status `open` → `linked` (or `rejected`).
* `firm_request_emails`: one row per requester (unique per request + email). Emails never leave the database except in mail.
* `request_firm(p_name, p_email, p_website, p_anon)` (anon + signed in). Returns `{status}`:
  `ok` (`already_requested` true when the same email asked before), `exists` (+ `slug`: the firm is already on the site),
  `bad_email`, `bad_name`, `bad_website`, `rate_limited`, `no_visitor`.
* Rate limits: 5 per visitor (anon id or account) per hour, 5 per IP per hour, 3 per email per day, 300 site-wide per hour.

## Queue (Researcher 3)
Since migration `20261024370000_researcher3_requests_only.sql` a new request is filed into `research_queue` right away
(`_firm_request_file`): `registry_id = 'req-<request id>'`, `lane = 'request'`, `list_source = 'firm_request'`, `paid_at` = when
first requested. No firm page is made for a request-lane row. Only `toxy-researcher-3` claims it, after paid checks
(docs/ON_DEMAND.md). If that row is already held by a normal-lane claim, filing the request releases the claim
immediately (same `_preempt_normal_claims` path as a paid job) and the previous bot's later upload is still accepted. When its valid research lands, trigger `zz_firm_request_done` links the request (`firm_request_link`) and moves the row
to the normal lane. The link does not create a firm. `firm_id` stays empty until a page exists, so no ready email goes
out yet. The page appears when `toxy-enricher` publishes; that call fills `firm_id` and files the to-do. If the dedupe
trigger matches the name to a firm that already has a page, the request is linked to that firm at once instead.

## For list builders
* View `firm_requests_open` (service role): id, name, website, website_domain, requesters, first/last requested. Most wanted first. No emails.
* RPC `firm_requests_list(p_limit)` (service role), or research-ingest `{"action": "firm_requests", "limit": 100}`.
* Optional: add the firm to `research_queue` as usual (its `req-<id>` row is then dropped as `skipped`). Adding a queue
  row does not create a page. A request with the same name key or website domain is **linked automatically**
  (trigger `zz_firm_request_link`) to a page that already exists. Link by hand: `select firm_request_link(<request id>, '<registry_id>')`.
  That keeps the link and the to-do and does not create a firm. Close without adding: `select firm_request_reject(<id>, 'reason')`.

## After linking
Once the request is linked to a firm that has a page, it goes through the step-4 on-demand flow (docs/ON_DEMAND.md): an
`ondemand_jobs` job plus one `research_requests` row per requester with `spend_kind = 'request'` (no credit, never
refunded), on the paid/priority lane. A link with no firm yet does not file that job. When the Enricher publishes the
page, each requester gets the "ready" email (`ready_request`).

## Emails (plain text, from support@regretamin.com via Resend, `ondemand-notify`)
* `received`: "We got your request for <firm>" (only within 2 days, only while not yet linked).
* `ready_request`: "<firm> is now on Regretamin" + link. Only when `research_requests.firm_request_id` is set.
  A notify-me signup on a firm that is already on the site (`check_requests`, `spend_kind = 'request'`, no
  `firm_request_id`) gets the `ready` email instead ("Your Regretamin check for <firm> is ready").

## Notify me vs Request this firm
`check_requests` (the "Email me when it's ready" box and the request-a-check form) is not a `firm_requests` row.
A firm already in the database is filed as a paid-lane on-demand job (docs/ON_DEMAND.md). A name that is not on the
site is filed as `registry_id = 'req-<check_requests id>'`, `lane = 'request'`, `list_source = 'check_request'`.
`firm_requests` uses the same `req-<id>` shape with `list_source = 'firm_request'`. If that registry id is already
taken, the check signup uses `req-c<id>` so the two lists cannot overwrite each other. A signup linked to a job
is marked notified and is not emailed a second time.
