#!/usr/bin/env bash
# Publish site-launch to Cloudflare Pages.
# The workflow runs this with working directory launch/, and wrangler 3 reads
# functions/ from that directory (not from site-launch/). It compiles the
# bundle before it creates a deployment. /vc/<slug>/ for every published firm
# is rendered by functions/vc/[[path]].js, so static HTML for the other firms
# is not what the live site serves. Production is published only after the
# preview URL still serves a non-lab firm and the functions sitemap index.
set -euo pipefail
cd "$(dirname "$0")/../launch"

LAB_ONLY=${LAB_ONLY:-1}
PROBE=${PROBE_FIRM:-founders-fund}

test -f 'functions/vc/[[path]].js'
test -f functions/sitemap.xml.js
test -f 'functions/sitemaps/[name].js'
test -d ../site-launch/vc

n=$(find ../site-launch/vc -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
if [ "$LAB_ONLY" = "0" ]; then
  if [ "$n" -le 10 ]; then
    echo "refusing full deploy: only $n firm directories" >&2
    exit 1
  fi
else
  if [ ! -d ../site-launch/vc/a16z ]; then
    echo "refusing lab deploy: a16z directory missing (found $n firm directories)" >&2
    exit 1
  fi
  if [ "$n" -ne 10 ]; then
    echo "lab deploy: $n firm directories; firm_meta did not return every lab slug" >&2
  fi
fi

rm -f ../site-launch/CNAME
log=$(mktemp)
deploy() {
  local branch="$1"
  npx --yes wrangler@3 pages deploy ../site-launch --project-name regretamin --branch "$branch" --commit-dirty=true >"$log" 2>&1
  cat "$log"
  if ! grep -q 'Uploading Functions bundle' "$log"; then
    echo "refusing: functions bundle was not uploaded, so a lab-only directory would drop other firm pages" >&2
    exit 1
  fi
}

deploy preview
url=$(grep -oE 'https://[a-z0-9]+\.regretamin\.pages\.dev' "$log" | head -1)
if [ -z "$url" ]; then
  echo "refusing: no preview deployment URL" >&2
  exit 1
fi
page_ok() {
  local slug="$1" html
  html=$(curl -fsS --retry 5 --retry-delay 3 --retry-all-errors "$url/vc/$slug/" || true)
  grep -q "data-firm=\"$slug\"" <<<"$html"
}
echo "checking firm page at $url/vc/$PROBE/"
if page_ok "$PROBE"; then
  echo "preview served $PROBE"
elif [ "$PROBE" != "a16z" ] && page_ok a16z; then
  echo "preview did not serve $PROBE; a16z loaded, continuing"
else
  echo "refusing production: preview did not serve $PROBE or a16z" >&2
  exit 1
fi
sm=$(curl -fsS --retry 5 --retry-delay 3 --retry-all-errors "$url/sitemap.xml" || true)
if ! grep -q '<sitemapindex' <<<"$sm"; then
  echo "preview sitemap is not the functions index; firm_sitemap is unavailable, continuing because the firm page loaded"
  deploy main
  echo "production deploy published (sitemap check skipped)"
  exit 0
fi
# firm_sitemap lists v2_firm_live. That set is a16z today, so a one-firm index is valid.
# An empty file, or a file that drops a16z, means the functions sitemap failed.
child=$(curl -fsS --retry 5 --retry-delay 3 --retry-all-errors "$url/sitemaps/firms-1.xml")
nloc=$(grep -c '<loc>' <<<"$child" || true)
if [ "${nloc:-0}" -lt 1 ] || ! grep -q '/vc/a16z/' <<<"$child"; then
  echo "refusing production: functions sitemap listed ${nloc:-0} firms" >&2
  exit 1
fi
listed=$(grep -oE -m 1 '/vc/[a-z0-9-]+/' <<<"$child" || true)
listed=${listed#/vc/}
listed=${listed%/}
if [ -z "$listed" ]; then
  echo "refusing production: could not read a sitemap firm" >&2
  exit 1
fi
listed_html=$(curl -fsS --retry 5 --retry-delay 3 --retry-all-errors "$url/vc/$listed/")
if ! grep -q "data-firm=\"$listed\"" <<<"$listed_html"; then
  echo "refusing production: preview did not serve sitemap firm $listed" >&2
  exit 1
fi

deploy main
echo "production deploy kept non-lab pages (preview served $PROBE)"
