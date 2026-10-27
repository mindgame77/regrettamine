# Regretamine

Founder tool for background-checking a VC fund before taking their money. The live site is [regretamin.com](https://regretamin.com), published by Cloudflare Pages from the launch build (`python3 launch/build.py` writes `site-launch/`).

The pages are plain HTML, CSS, and JavaScript. Login is Google or an email link (`/login/`). Account is at `/account/`. Plans and checkout are at `/plans/`. See `launch/HOW-TO-CHANGE.md` for what to edit.

`python3 launch/build.py` writes `site-launch/`. That is the site Cloudflare publishes.

## Run it locally

```bash
python3 launch/build.py
python3 -m http.server -d site-launch 8000
```

Open [http://localhost:8000/](http://localhost:8000/). `site-launch/` is generated. Do not edit it by hand. Python 3.9 or newer is enough. There is no install step.

## Dates

Every date a visitor sees on the launch site (`launch/`, served at regretamin.com) goes through `launch/js/dates.js` (`RegretDate`). A date on its own is `Mar 15, 2024`. Where a time is shown it is Pacific: `Mar 15, 2024, 3:58 PM PT`. New pages and templates use that helper. Do not call `toLocaleDateString` or format a date by hand.

The live host is the domain root (`https://regretamin.com/`). Links in the launch build are root-relative.

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
5. Push to `main`. The workflow passes `SUPABASE_URL` and `SUPABASE_ANON_KEY` into `launch/build.py`, which publishes to Cloudflare. If either secret is missing, the launch build falls back to `data/launch/`.

Anon can read published firms only. A signed-in person can insert their own watchlist rows, alert preferences, report views, and pending reviews. Writes in the Table Editor use the logged-in dashboard role, which bypasses row-level security. The anon key cannot insert or update content.

### Auth in the Supabase dashboard

The launch site talks to Supabase Auth from the browser (`@supabase/supabase-js` on a CDN). `launch/build.py` embeds `SUPABASE_URL` and `SUPABASE_ANON_KEY`. Only the publishable key is embedded.

In the Supabase dashboard for this project (these fields are dashboard settings; this repo does not push them):

1. **Authentication → Providers → Google**: turn it on. Create an OAuth client in Google Cloud (authorized redirect `https://<project-ref>.supabase.co/auth/v1/callback`) and paste the Client ID and Client secret. Leave GitHub off. Email magic link is on for the launch site.
2. **Authentication → URL configuration**
   - Site URL: `https://regretamin.com/`
   - Redirect URLs: `https://regretamin.com/**` so Google and the email link can return to the page the person was on (`/`, `/login/`, `/account/`, `/plans/`, `/vc/<slug>/`).
3. **Authentication → Email templates**: the repo copies are `supabase/templates/confirmation.html`, `email_change.html`, and `recovery.html`. The dashboard templates are separate. Point their logo at `https://regretamin.com/assets/logo/lockup-light@2x.png`.

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

Pushes to `main` run `.github/workflows/pages.yml`. The launch build is `python3 launch/build.py` (output `site-launch/`). The `cloudflare-preview` job publishes that directory to the Cloudflare Pages project `regretamin`: a preview branch, then production. Production is **https://regretamin.com/** (and `regretamin.pages.dev`). The live page check runs after that production deploy.

Check a change locally before deploying:

```bash
python3 launch/build.py
python3 -m http.server -d site-launch 8000
```

Open [http://localhost:8000/](http://localhost:8000/).
