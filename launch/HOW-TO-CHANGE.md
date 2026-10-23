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
| Shown prices, plan names, "per check", features, "Most picked" | `launch/copy.json` → `plans` (both pricing popups are drawn from it by `js/app.js`; `amount` = dollars, used for code discounts) | `launch/deploy_preview.sh` |
| Yearly prices, "Save $38", "2 months free" | `launch/copy.json` → `plans.m10.yearly` / `plans.m30.yearly`, toggle words in `site.billing` | `launch/deploy_preview.sh` |
| "Have a code?" field wording, code messages, code-unlocked plan card | `launch/copy.json` → `site.code` and `js.code_*` / `js.dur_*` / `js.off_*` | `launch/deploy_preview.sh` |
| Exit-survey answers (cancel / delete) | `launch/copy.json` → `site.account.reasons` **and** the allowed list in `supabase/functions/_shared/exit_reason.ts` + `exit_reasons` check constraint (new value = migration) | deploy function + `launch/deploy_preview.sh` |
| Colors, spacing, fonts | `launch/style.css` (pill colors: `.p-ok/.p-rev/.p-red/.p-g`) | `launch/deploy_preview.sh` |
| Page layout / HTML structure | `launch/build.py` (no copy in it, only markup) | `launch/deploy_preview.sh` |
| How a section's items are drawn | `launch/js/company.js` (`R.<renderer>`) | `launch/deploy_preview.sh` |
| What Stripe actually charges (amount) | Stripe: new Price, then Supabase Edge Function secret `STRIPE_PRICE_SINGLE` / `_M10` / `_M30` / `_Y10` / `_Y30`; also update shown price in `copy.json` → `plans` | `supabase secrets set ...` + `launch/deploy_preview.sh` |
| Checks granted per month (monthly and yearly plans) | `supabase/functions/regretamin-stripe-webhook/index.ts` `PLAN`, `supabase/functions/create-checkout/index.ts` `CHECKS` **and** `copy.json` → `plans.*.checks` | deploy webhook function + `launch/deploy_preview.sh` |
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
| Stripe price IDs | Supabase function secrets `STRIPE_PRICE_SINGLE`, `STRIPE_PRICE_M10`, `STRIPE_PRICE_M30`, `STRIPE_PRICE_Y10`, `STRIPE_PRICE_Y30` |
| Webhook signing secret | Supabase function secret `REGRETAMIN_STRIPE_WEBHOOK_SECRET` |
| Checkout return URL | Supabase function secret `SITE_URL` |
| Email sender | Supabase Auth → SMTP settings (dashboard) |

Check a change locally before deploying: `python3 launch/build.py && python3 -m http.server -d site-launch` → http://localhost:8000/

## Yearly plans
- Billed once a year by Stripe; checks still refill **monthly**. The webhook stores `monthly_checks` and `next_refill` on `check_balances`;
  the DB cron job `regretamin-refill-yearly` (`refill_yearly_checks()`, every hour at :07) resets `paid_left` to `monthly_checks` when `next_refill` has passed.
- Codes: the site asks the `validate-code` function whether a code is valid (so it can show the new price); `create-checkout` checks it again and Stripe applies the discount.

## How to make a secret code
Codes live only in Stripe (no repo or DB change). Make them in **Test mode** first and try them on the preview; then repeat in Live mode.

**A discount code (e.g. FOUNDER50):**
1. Stripe Dashboard → **Product catalog → Coupons → + Create coupon**.
2. Pick **Percentage** (e.g. 50) or **Fixed amount** (USD), and **Duration**: Once / Multiple months (e.g. 3) / Forever.
   On a yearly plan, "Once" and "Multiple months" both mean the first year's payment.
3. Optional: **Apply to specific products** → choose e.g. Regretamin Starter. Without it the code works on every plan, including Single check.
4. Save, open the coupon → **Promotion codes → + Add promotion code** → type the code customers enter (e.g. `FOUNDER50`; the site makes it upper case).
   Optional: limit redemptions or set an expiry date.
5. Done: it works on the site right away (popup → "Have a code?").

**A secret plan unlocked by a code (e.g. ANGEL → "Fund scout"):**
1. **Product catalog → + Add product**, e.g. "Regretamin Fund scout", recurring price (e.g. $99 / month or / year).
2. On that **price** (open it → Metadata), add: `hidden` = `true`, `checks` = checks per month (e.g. `100`), `name` = name shown on the site (e.g. `Fund scout`).
3. Make a coupon (any; e.g. 1% Once if you only want to unlock) and a promotion code for it (steps above), and on the **promotion code** add metadata
   `unlock_price` = the price ID (`price_…`) from step 1. Add `unlock_only` = `true` if the code should unlock the plan without any discount.
4. Customers who enter the code see a dashed "Unlocked with code" card; checks per month come from the price's `checks`.

To stop a code: open the promotion code → **Archive** (or make it inactive). Live codes need the same steps in Live mode (price IDs differ).
