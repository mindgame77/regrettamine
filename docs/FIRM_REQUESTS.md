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

## For list builders
* View `firm_requests_open` (service role): id, name, website, website_domain, requesters, first/last requested. Most wanted first. No emails.
* RPC `firm_requests_list(p_limit)` (service role), or research-ingest `{"action": "firm_requests", "limit": 100}`.
* Add the firm to `research_queue` as usual. A request with the same name key or website domain is **linked automatically**
  (trigger `zz_firm_request_link`). Link by hand: `select firm_request_link(<request id>, '<registry_id>')`.
  Close without adding: `select firm_request_reject(<id>, 'reason')`.

## After linking
The firm goes through the step-4 on-demand flow (docs/ON_DEMAND.md): an `ondemand_jobs` job plus one `research_requests`
row per requester with `spend_kind = 'request'` (no credit, never refunded), on the paid/priority lane. When the research
lands and the page is live, each requester gets the "ready" email (`ready_request`).

## Emails (plain text, from support@regretamin.com via Resend, `ondemand-notify`)
* `received`: "We got your request for <firm>" (only within 2 days, only while not yet linked).
* `ready_request`: "<firm> is now on Regretamin" + link.
