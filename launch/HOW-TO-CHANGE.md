# How to change the launch site

Rule: **anything you see (words, prices shown, section titles/order, colors) is a repo file. No DB change needed.**
The database only holds facts about firms and per-user data.

After any repo edit below: `launch/deploy_preview.sh` → preview at https://mindgame77.github.io/regretamin-preview/ (about 1 min).
It never touches the live site (mindgame77.github.io/regrettamine).

| Want to change | Edit | Then run |
|---|---|---|
| Any visible text (landing hero, chips, press list, nav, modals, account, my checks, pending page) | `launch/copy.json` → `site` | `launch/deploy_preview.sh` |
| Messages made by the browser code (check counts, banners, errors, "Cancelling", delete steps) | `launch/copy.json` → `js` (`{x}` = filled-in value; `[one, many]` picked by count) | `launch/deploy_preview.sh` |
| Company page wording (table of contents, lock card, "Open with 1 check", legal/people group labels) | `launch/copy.json` → `company` | `launch/deploy_preview.sh` |
| Company page sections: title, subtitle, order, unit labels (fact/facts), which renderer, hide one | `launch/copy.json` → `sections.list` (order = list order; delete an entry to hide it) | `launch/deploy_preview.sh` |
| Shown prices, plan names, "per check", features, "Most picked" | `launch/copy.json` → `plans` (both pricing popups are generated from it) | `launch/deploy_preview.sh` |
| Exit-survey answers (cancel / delete) | `launch/copy.json` → `site.account.reasons` **and** the allowed list in `supabase/functions/_shared/exit_reason.ts` + `exit_reasons` check constraint (new value = migration) | deploy function + `launch/deploy_preview.sh` |
| Colors, spacing, fonts | `launch/style.css` (pill colors: `.p-ok/.p-rev/.p-red/.p-g`) | `launch/deploy_preview.sh` |
| Page layout / HTML structure | `launch/build.py` (no copy in it, only markup) | `launch/deploy_preview.sh` |
| How a section's items are drawn | `launch/js/company.js` (`R.<renderer>`) | `launch/deploy_preview.sh` |
| What Stripe actually charges (amount) | Stripe: new Price, then Supabase Edge Function secret `STRIPE_PRICE_SINGLE` / `_M10` / `_M30`; also update shown price in `copy.json` → `plans` | `supabase secrets set ...` + `launch/deploy_preview.sh` |
| Checks granted per monthly plan | `supabase/functions/regretamin-stripe-webhook/index.ts` `PLAN` **and** `copy.json` → `plans.*.checks` | deploy webhook function + `launch/deploy_preview.sh` |
| Firm facts, cases, press items, people, checks results | DB: `firms`, `firm_profile_facts`, check tables (via `launch/sync_checks.py` → migration) | migration (backup first) |

## Presentation vs data
- **Repo (presentation):** `launch/copy.json` (all copy, plans, section titles/subtitles/order/units/renderer), `launch/style.css` (colors), `launch/build.py` (markup), `launch/js/*` (behavior).
- **DB (data):** firms and their facts; `firm_page()` returns per section only `key`, `count`, `teaser`, `items`.
  `company.js` shows a section only if it is in `copy.json` `sections.list` **and** the DB returned it, and takes every display field from `copy.json`.
- `page_sections` is now only the list of data keys (`key`, `enabled`, `sort_order` decide what `firm_page()` returns).
  Its `title`, `subtitle`, `renderer`, `unit_one`, `unit_many` columns are **no longer used by the site**; dropping them is optional cleanup (migration + backup, ask Alex).
- A brand-new section = add its data in the DB under a new key (migration) + an entry in `sections.list`.

## Secrets / config (not in the repo)
| What | Where |
|---|---|
| Supabase URL + anon key (public) | build env `SUPABASE_URL`, `SUPABASE_ANON_KEY` (deploy_preview.sh fills them) |
| Stripe secret key | Supabase function secret `STRIPE_SECRET_KEY` (create-checkout, webhook) **and** DB `app_secrets` row `stripe_secret_key` (cancel-subscription, delete-account, billing-portal) — keep both the same |
| Stripe price IDs | Supabase function secrets `STRIPE_PRICE_SINGLE`, `STRIPE_PRICE_M10`, `STRIPE_PRICE_M30` |
| Webhook signing secret | Supabase function secret `REGRETAMIN_STRIPE_WEBHOOK_SECRET` |
| Checkout return URL | Supabase function secret `SITE_URL` |
| Email sender | Supabase Auth → SMTP settings (dashboard) |

Check a change locally before deploying: `python3 launch/build.py && python3 -m http.server -d site-launch` → http://localhost:8000/
