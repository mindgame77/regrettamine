# Regretamin design

- Rules: [`.cursor/rules/design.mdc`](../../.cursor/rules/design.mdc) (always applied)
- Tokens: [`src/css/tokens.css`](../../src/css/tokens.css) · components layer: [`src/css/common.css`](../../src/css/common.css)
- Copy and text variants: [`src/js/strings.js`](../../src/js/strings.js) · Supabase table `ui_strings` (migration `20261014120000_ui_strings.sql`, **not applied yet**)
- Catalog: [`docs/design/catalog/index.html`](catalog/index.html). Open it from a local checkout; it reads the live CSS and strings.

## Logo
Chosen: **C1** (Oct 14, 2026) from the design workspace, `logo/explore-4.html`. Violet capsule `#6C3BFF` with white tick, ink "Regretamin" wordmark (outlined Bricolage Grotesque 800).
- Files in `assets/logo/`:
  - `lockup-light.svg` and `lockup-dark.svg`
  - `icon-light.svg` and `icon-dark.svg`
  - `fav32-*.svg` and `fav16-*.svg`
  - `favicon-16.png`, `favicon-32.png`, `apple-touch-icon.png` (180), `icon-192.png`, `icon-512.png`
  - `lockup-light@2x.png` (emails) and `og.png` (1200×630)
- Also `assets/favicon.ico` (16/32/48) and `assets/favicon.svg`.
- Usage: nav uses `.logo .lockup` at 36px; footer uses `.lockup.sm` at 28px. Minimum sizes: lockup 24px, icon 16px. Clear space: at least the capsule height on every side. On dark backgrounds use the `-dark` files.
- Don't recolour, stretch, re-type the wordmark as live text, add effects, or put the light lockup on violet or busy backgrounds.
- Logo explorations `logo/ideas.html`, `explore-2.html`, `explore-3.html`, `explore-4.html` (all except C1), `svg/`, `svg2/`, `svg3/`, and other files in `svg4/` are **HISTORY**. The old conic-gradient ring logo is **HISTORY**.

## Approved mockups
Mockups are kept outside the repo in the design workspace (`toxybase/design/`). Status: **SHIPPED** = live matches, **APPROVED** = approved, not built yet, **HISTORY** = outdated, do not build from it.

| Mockup | Status | Diffs vs shipped |
|---|---|---|
| `landing/regret-fund.html` (fund page, Score/Public tabs) | SHIPPED | Mock nav shows "VCs · How it works · Scoring"; live is "VCs · Scoring · Pricing" (live wins). Mock verdict said "Safe to take a meeting"; now "Reasonable to take a meeting". |
| `landing/regret-v3.html` (landing: fund list, filters, latest updates) | SHIPPED | Live adds the 4th stat "funds sanctioned" and search hint. Will move to the VCs page under the trust-check plan. |
| `landing/pricing-1/` | SHIPPED (as `/plans/`) | Live adds the $1 test purchase button (admin only). |
| `landing/settings-1/` | SHIPPED (as `/settings/`) | none known |
| `landing/regret-login.html` | SHIPPED (as `/login/` + auth modal) | none known |
| `trust/landing-combined-v2.html` (trust-check landing) | APPROVED | Not built. Uses stats strip under search, databases checklist, Full dossier paywall, sample report frames. |
| `trust/app-1-home.html`, `app-2-search.html`, `app-3-vc-view.html` (logged-in flow) | APPROVED (proposal) | Not built. app-3 tabs used violet-filled style; build with the live segmented tabs. Toggle size 46×26 in mock; use live 42×24. |
| `trust/flow-0…6-*.html` (trust-check flow and access logic) | APPROVED (proposal) | Not built. Report-limit copy changes only with the new free-check model. |
| `trust/landing-combined.html` (v1) | **HISTORY** | Superseded by v2. |
| `trust/idea-1/2/3.html` | **HISTORY** | Combined into landing-combined-v2. |
| `landing/option-1-*`, `option-2-*`, `regret-a.html`, `regret-b.html`, `regret-home-200.html`, `edits-*` | **HISTORY** | Earlier explorations; superseded by regret-v3 and regret-fund. |
| `system/index.html`, `system/ds-landing.html` (first draft style guide) | **HISTORY** | Superseded by this catalog and tokens.css. |

## Audit and decisions (Oct 14, 2026)
- Full audit: `toxybase/design/system/audit/AUDIT.md` (pages, tokens in use, hardcoded facts/strings, data sources).
- Brand shown to users: **Regretamin** (`brand.name`). Domain regretamine.com and path /regrettamine/ unchanged.
- Approved wording: "Reasonable to take a meeting" (a16z verdict); Scoring step 03 "higher means fewer red flags in the sources we checked".
- Logo C1 replaces the conic ring + live-text wordmark in nav, footer, 404, auth pages, fund pages and email templates. Favicons on every page.
- Weight 600 was used but never loaded (browsers already rendered 700). Mapped to 700; screenshots show no change. Bricolage 500 was loaded but unused; dropped.
- `/reset/` now redirects to `/login/reset/` (keeps query and hash).

## Not done yet (next steps)
- Move remaining inline copy (about 1,300 strings in `src/*.html`, `src/js/*.js`, `build.py`) into strings.js. Wired so far: brand, auth modal headings/sublines/submit, score bands, sentiment labels, plan buttons, scoring step 03.
- Load `strings.js` on every page and call `RS.load()` after `ui_strings` is applied.
- Collapse near-duplicate hardcoded colours and half-pixel font sizes to tokens (visual review per page).
- Move all facts to Supabase at runtime and add the data workers: SEC, sanctions, courts/DOJ, news, score recompute.
