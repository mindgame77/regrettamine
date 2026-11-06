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

# An older main run must not publish. PR 339 deployed while PR 340 was already
# on main, so production served that older company.js (inline Show all) until
# the newer run finished. Wrangler then reported the bytes "already uploaded".
if [ -n "${GITHUB_SHA:-}" ]; then
  git fetch --no-tags --depth=1 origin main
  tip=$(git rev-parse origin/main)
  if [ "$tip" != "$GITHUB_SHA" ]; then
    echo "refusing deploy: this build is ${GITHUB_SHA} but origin/main is ${tip}" >&2
    exit 1
  fi
fi

sha10() { sha1sum "$1" | awk '{print substr($1,1,10)}'; }
for pair in \
  'js/company.js:../site-launch/company.js' \
  'js/app.js:../site-launch/app.js' \
  'js/search.js:../site-launch/search.js' \
  'js/dates.js:../site-launch/dates.js' \
  'style.css:../site-launch/style.css'
do
  src=${pair%%:*}
  dst=${pair#*:}
  a=$(sha10 "$src")
  b=$(sha10 "$dst")
  if [ "$a" != "$b" ]; then
    echo "refusing: $dst is $b but $src is $a" >&2
    exit 1
  fi
done
ASSET_HASH=$(sha10 js/company.js)
for page in ../site-launch/_tpl/full.html ../site-launch/vc/a16z/full/index.html; do
  if ! grep -q "company.js?v=${ASSET_HASH}" "$page"; then
    echo "refusing: $page does not reference company.js?v=${ASSET_HASH}" >&2
    exit 1
  fi
done
echo "site-launch matches this commit ($ASSET_HASH)"

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
# The preview deployment is a new URL, so it is not the cached production file.
# Production is published only when that URL is serving this commit's company.js.
preview_matches_source() {
  local html got
  html=$(curl -fsS --retry 5 --retry-delay 3 --retry-all-errors "$url/vc/a16z/full/")
  if ! grep -q "company.js?v=${ASSET_HASH}" <<<"$html"; then
    echo "refusing production: preview HTML does not reference company.js?v=${ASSET_HASH}" >&2
    exit 1
  fi
  got=$(curl -fsS --retry 5 --retry-delay 3 --retry-all-errors "$url/company.js" | sha1sum | awk '{print substr($1,1,10)}')
  if [ "$got" != "$ASSET_HASH" ]; then
    echo "refusing production: preview company.js is $got, source is $ASSET_HASH" >&2
    exit 1
  fi
  echo "preview company.js matches source $ASSET_HASH"
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
  preview_matches_source
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

preview_matches_source
deploy main
echo "production deploy kept non-lab pages (preview served $PROBE)"
