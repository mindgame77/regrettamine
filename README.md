# Regretamine

Founder tool for background-checking a VC fund before taking their money. This repo is the static site for [regretamin.com](https://regretamin.com): the fund list at `/` and the Andreessen Horowitz report at `/vc/a16z/`.

The pages are plain HTML, CSS, and JavaScript. `build.py` turns either the JSON in `data/` or a Supabase Postgres database into the site. Login is Google or email and password (`/login/`). A free account is at `/account/` (watchlist, alerts, share experience). Anonymous visitors get 2 reports, an account gets 5 more, then a plans placeholder with no prices and no checkout. The watchlist uses the same fund list as the homepage.

## Run it locally

```bash
python3 build.py
python3 -m http.server -d site 8000
```

Open [http://localhost:8000/](http://localhost:8000/) and [http://localhost:8000/vc/a16z/](http://localhost:8000/vc/a16z/).

## Dates

Every date a visitor sees on the launch site (`launch/`, served at regretamin.com) goes through `launch/js/dates.js` (`RegretDate`). A date on its own is `Mar 15, 2024`. Where a time is shown it is Pacific: `Mar 15, 2024, 3:58 PM PT`. New pages and templates use that helper. Do not call `toLocaleDateString` or format a date by hand.

`site/` is generated. Do not edit it by hand. Python 3.9 or newer is enough. There is no install step.

Links and assets are relative, so the same build works at the project URL (`https://<user>.github.io/regrettamine/`) and at the domain root (`https://regretamin.com/`). No base-path setting.

## Add a fund in JSON

This is the fallback, used when the Supabase secrets are not set. Once Supabase is connected, add firms in the Table Editor (see below) instead of editing these files.

List row (shows on the homepage, no report yet):

Firms, reports and scores live in Supabase only. Add or edit rows there; the build renders every page from `published_site_bundle()`.

## Supabase

The model is `docs/data-model.md`. A **firm** is the management company (the `/vc/<slug>/` page). A firm has many **funds** (vehicles). People, portfolio companies, reviews, legal matters, and sources are rows, so a firm can have thousands of companies without a fixed set of columns. Scores are versioned (`score_results` + `score_inputs`). Test rows (`is_test`) cannot be published.

One-time setup:

1. Create a free project at [supabase.com](https://supabase.com).
2. In the SQL editor, run the files in `supabase/migrations/` in name order (`20261004120000_schema.sql`, `20261004120100_rls.sql`, `20261004140000_auth_account.sql`, then `20261004180000_share_review.sql`). Or, with the database URL from **Project Settings → Database**:

   ```bash
   pip install -r requirements-dev.txt
   DATABASE_URL="postgresql://postgres.[ref]:[password]@aws-0-[region].pooler.supabase.com:5432/postgres" python3 scripts/migrate.py
   DATABASE_URL="…" python3 scripts/seed.py
   ```

   `seed.py` (test databases only, never live) loads `tests/fixtures/db_snapshot.json`, an export of the live content tables. It replaces those content tables. It does not invent vehicles, portfolio companies, reviews, or users. It does not load `templates/csv/`. The account migration adds the signup trigger, the watchlist cap, alert preferences, and the rule that a founder review stays hidden until it is approved. `20261004180000_share_review.sql` adds the share-form columns (connection type, five ratings, LinkedIn URL). The LinkedIn URL is not selectable by anon or signed-in users and is omitted from the public bundle. `first_hand` and `verification_status` stay at the server defaults for those roles.

3. **Project Settings → API**: copy the project URL and the `anon` public key.
4. GitHub → this repo → **Settings → Secrets and variables → Actions**. Add:
   - `SUPABASE_URL` — the project URL
   - `SUPABASE_ANON_KEY` — the publishable key (`sb_publishable_...`) is recommended. The legacy anon JWT also works. Both were tested against the live project and the build matched the JSON output. `SUPABASE_URL` and `SUPABASE_ANON_KEY` are set on this repo.
5. Re-run **Deploy to GitHub Pages** (or push to `main`). The workflow passes the secrets into `build.py`. If either secret is missing, the workflow keeps building from `data/`.

Anon can read published firms only. A signed-in person can insert their own watchlist rows, alert preferences, report views, and pending reviews. Writes in the Table Editor use the logged-in dashboard role, which bypasses row-level security. The anon key cannot insert or update content.

### Auth in the Supabase dashboard

The site talks to Supabase Auth from the browser (`@supabase/supabase-js` on a CDN). `build.py` writes `site/js/supabase-config.js` from `SUPABASE_URL` and `SUPABASE_ANON_KEY`. Only the publishable key is embedded.

In the Supabase dashboard for this project:

1. **Authentication → Providers → Google**: turn it on. Create an OAuth client in Google Cloud (authorized redirect `https://<project-ref>.supabase.co/auth/v1/callback`) and paste the Client ID and Client secret. Leave GitHub off. Leave magic link / email OTP off. Email + password stays on.
2. **Authentication → URL configuration**
   - Site URL: `https://mindgame77.github.io/regrettamine/`
   - Redirect URLs: `https://mindgame77.github.io/regrettamine/` and `https://mindgame77.github.io/regrettamine/login/reset/`
3. If **Confirm email** is on, the extra 5 reports stay locked until the person confirms. Google accounts are already confirmed.

No Stripe and no prices. The plans card says the price is not set.

### Add or edit a firm

**Table Editor** (no code):

1. `firms` — one row. `slug` is the id (`sequoia`). Set `published` when it should show on the list. Leave `report_slug` empty until the report is ready; the row stays “coming soon”. Set `report_slug` to the same slug to publish `/vc/<slug>/`.
2. `funds` — one row per vehicle (name, vintage, size, status). `firm_id` is the firm.
3. `people`, then `fund_people` — one row per role, with start and end dates. The same person can have rows at more than one firm.
4. `portfolio_companies`, then `investments` — round, date, lead, board seat, outcome. Add founders in `company_founders`.
5. `legal_matters`, then `legal_matter_firms` — the firm’s role (plaintiff or defendant), status, counted or not, relevance. Parties, filings, and docket entries are further rows.
6. `press_items` (`sentiment` is `pos`, `neu`, or `neg`) and `press_item_firms`.
7. `sources` — one row per URL (`verified`, `junk`). `fact_sources` links a source to any fact (`fact_type`, `fact_id`).
8. A full report also needs `copy_blocks`, `takeaways`, `ask_questions`, `evidence_cards`, and a current `score_results` row (version `v2`) with `score_inputs`. The score function reads those inputs.

**CSV:** `templates/csv/` has worksheets for funds (vehicles), legal matters, people, and press. Each file has one row with `example` = `yes`. That row is skipped. Fill a copy of the file, then:

```bash
DATABASE_URL="…" python3 scripts/import_csv.py funds templates/csv/funds.csv
DATABASE_URL="…" python3 scripts/import_csv.py legal templates/csv/legal_matters.csv
DATABASE_URL="…" python3 scripts/import_csv.py people templates/csv/people.csv
DATABASE_URL="…" python3 scripts/import_csv.py press templates/csv/press_items.csv
```

`firm_slug` must already be a row in `firms`. The example rows are not part of the seed. You can also type the same fields straight into the Table Editor; the CSV headers are the field list.

Do not set `published` on a row with `is_test` true. The database rejects it. `scripts/stress_fixture.py` loads one fake firm (`stress-fixture`, 3 vehicles, 20 people, 1,000 companies, 100 reviews, 150 sources) for a pagination check. It stays unpublished and the site build never selects it.

## Deploy

Pushes to `main` run `.github/workflows/pages.yml`, which builds `site/` and deploys it with GitHub Actions.

The repository owner has to turn Pages on once:

1. GitHub → this repo → **Settings → Pages**.
2. Under **Build and deployment**, set **Source** to **GitHub Actions**.
3. Merge to `main` (or re-run the “Deploy to GitHub Pages” workflow).
4. When the deploy job is green, the site is at **https://mindgame77.github.io/regrettamine/**.

If the deploy fails with a Pages site error before that setting is saved, set the source and re-run the workflow. The URL is also printed on the workflow run and on the Pages settings screen.

### Custom domain (regretamin.com)

A `CNAME` file is not in the repo yet, so the `github.io` URL keeps working before DNS exists. When you are ready:

1. Add a file named `CNAME` at the repo root whose only line is `regretamin.com`. `build.py` copies it into the published site. Commit it to `main`.
2. At the DNS host, point the apex at GitHub Pages:
   - `A` records for `@`: `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153`
   - or an `ALIAS` / `ANAME` / apex `CNAME` to `mindgame77.github.io`, if the host supports it
   - `www` as a `CNAME` to `mindgame77.github.io`
3. Settings → Pages → **Custom domain**: `regretamin.com`. After DNS checks out, turn on **Enforce HTTPS**.

Relative links mean you do not change paths when the custom domain goes live.
