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
  if [ "$n" -ne 10 ]; then
    echo "refusing lab deploy: expected 10 firm directories, found $n" >&2
    exit 1
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
echo "checking non-lab firm at $url/vc/$PROBE/"
html=$(curl -fsS --retry 5 --retry-delay 3 --retry-all-errors "$url/vc/$PROBE/")
if ! grep -q "data-firm=\"$PROBE\"" <<<"$html"; then
  echo "refusing production: preview did not serve non-lab firm $PROBE" >&2
  exit 1
fi
sm=$(curl -fsS --retry 5 --retry-delay 3 --retry-all-errors "$url/sitemap.xml")
if ! grep -q '<sitemapindex' <<<"$sm"; then
  echo "refusing production: preview sitemap is not the functions sitemap index" >&2
  exit 1
fi
child=$(curl -fsS --retry 5 --retry-delay 3 --retry-all-errors "$url/sitemaps/firms-1.xml")
if ! grep -q "/vc/$PROBE/" <<<"$child"; then
  echo "refusing production: sitemap does not list non-lab firm $PROBE" >&2
  exit 1
fi

deploy main
echo "production deploy kept non-lab pages (preview served $PROBE)"
