# Regretamin launch (v1)
Two pages: search (`/`) and one result template per firm (`/vc/<slug>/`), plus `/pending/` for unknown firms. Pricing opens as a modal from the nav.
Build: `python3 launch/build.py` -> `site-launch/`. Copy, plans and section presentation: `launch/copy.json`. Deploy to preview: `launch/deploy_preview.sh`. What to edit for each kind of change: [HOW-TO-CHANGE.md](HOW-TO-CHANGE.md).
Data: `data/launch/<slug>.json` = output of `launch/firm_snapshot.sql` (read-only, `:slug`). Row logic in `launch/checks.py`: pills only, no verdict/score, name-only hits dropped.

## To go live
1. Back up prod (`supabase db dump`), report, then apply `supabase/migrations/20261022120000_launch_checks.sql`. Tested on local Postgres 17 (anon 2 -> sign-up +4 -> plan grant, re-open free, webhook idempotent).
2. Supabase Auth: enable Google (OAuth client id + secret, redirect `https://sxxgvkdwgiouyqciztec.supabase.co/auth/v1/callback`), enable email magic link, set Site URL + redirect URLs. Set up custom SMTP for magic-link volume.
3. Stripe sandbox: `STRIPE_SECRET_KEY=sk_test_... python3 scripts/stripe_sandbox_products.py` -> price ids.
4. Edge functions: `create-checkout`, `stripe-webhook` (`--no-verify-jwt`). Secrets: STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, STRIPE_PRICE_SINGLE/M10/M30, SITE_URL. Webhook events: checkout.session.completed, invoice.paid.
5. Worker for `check_requests` (queued -> run checks -> write firm/facts -> email). Not built yet.
6. `firm_details()` is a stub: move the details/sources rendering in there so it's only served after a check is spent.
