# Regrettamine

Founder tool for background-checking a VC fund before taking their money. This repo is the static site for [regrettamine.com](https://regrettamine.com): the fund list at `/` and the Andreessen Horowitz report at `/vc/a16z/`.

The pages are plain HTML, CSS, and JavaScript. A small Python script (`build.py`, standard library only) turns the JSON in `data/` into the site. Login, alerts, registration, and the paywall are not built. Those buttons are visual only.

## Run it locally

```bash
python3 build.py
python3 -m http.server -d site 8000
```

Open [http://localhost:8000/](http://localhost:8000/) and [http://localhost:8000/vc/a16z/](http://localhost:8000/vc/a16z/).

`site/` is generated. Do not edit it by hand. Python 3.9 or newer is enough. There is no install step.

Links and assets are relative, so the same build works at the project URL (`https://<user>.github.io/regrettamine/`) and at the domain root (`https://regrettamine.com/`). No base-path setting.

## Add a fund

List row (shows on the homepage, no report yet):

1. Copy an object in `data/home.json` → `funds`.
2. Fill it from a real record. Fields the list uses: `id`, `name`, `hq`, `since`, `aum`, `aumAsOf`, `aumStale`, `score`, `v2`, `band`, `legal`, `legalNote`, `updated`, `updatedTs`, `updatedS`. A v2 row also needs `lo` and `hi` (and usually `short`).
3. Leave `"report": null`. The row stays “coming soon” and does not open a page.

Full report:

1. Set `"report"` to a slug, for example `"sequoia"`.
2. Copy `data/funds/a16z.json` to `data/funds/sequoia.json` and set `"slug"` to the same value. The filename, `slug`, and `report` must match.
3. Replace the copy with that fund’s own records. The page is rendered from this file: hero, score parts, legal matters, people, public items, portfolio, questions, and the `evidence` object behind every popup. Keep the shape. Do not add facts that are not sourced.
4. Run `python3 build.py`. It writes `site/vc/<slug>/index.html` and fails if a `report` slug has no JSON file, or if a button points at a missing evidence id.

Scores, stats, and the update feed on the homepage also live in `data/home.json` (`stats`, `updates`). An update whose `fid` matches a fund with a `report` links the fund name to that report. Use a full `https://` URL in `u` for an external source.

`docs/toxy-score-v2-rules.md` is the Toxy Score v2 rules the a16z score is based on.

## Deploy

Pushes to `main` run `.github/workflows/pages.yml`, which builds `site/` and deploys it with GitHub Actions.

The repository owner has to turn Pages on once:

1. GitHub → this repo → **Settings → Pages**.
2. Under **Build and deployment**, set **Source** to **GitHub Actions**.
3. Merge to `main` (or re-run the “Deploy to GitHub Pages” workflow).
4. When the deploy job is green, the site is at **https://mindgame77.github.io/regrettamine/**.

If the deploy fails with a Pages site error before that setting is saved, set the source and re-run the workflow. The URL is also printed on the workflow run and on the Pages settings screen.

### Custom domain (regrettamine.com)

A `CNAME` file is not in the repo yet, so the `github.io` URL keeps working before DNS exists. When you are ready:

1. Add a file named `CNAME` at the repo root whose only line is `regrettamine.com`. `build.py` copies it into the published site. Commit it to `main`.
2. At the DNS host, point the apex at GitHub Pages:
   - `A` records for `@`: `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153`
   - or an `ALIAS` / `ANAME` / apex `CNAME` to `mindgame77.github.io`, if the host supports it
   - `www` as a `CNAME` to `mindgame77.github.io`
3. Settings → Pages → **Custom domain**: `regrettamine.com`. After DNS checks out, turn on **Enforce HTTPS**.

Relative links mean you do not change paths when the custom domain goes live.
