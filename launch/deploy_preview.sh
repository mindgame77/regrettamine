#!/usr/bin/env bash
# Build launch/ and publish it to the PREVIEW site only: https://mindgame77.github.io/regretamin-preview/
# Usage: launch/deploy_preview.sh            (needs git push access to mindgame77/regretamin-preview)
# Env (optional): PREVIEW_DIR (default: a regretamin-preview clone next to this repo), SUPABASE_URL, SUPABASE_ANON_KEY
# (public anon key; if unset it is read from the current preview build). Stripe price IDs are NOT build inputs:
# they are Supabase Edge Function secrets (see launch/HOW-TO-CHANGE.md).
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
PREVIEW_DIR=${PREVIEW_DIR:-$(dirname "$REPO")/regretamin-preview}
[ -d "$PREVIEW_DIR/.git" ] || git clone https://github.com/mindgame77/regretamin-preview.git "$PREVIEW_DIR"
case "$(git -C "$PREVIEW_DIR" remote get-url origin)" in
  *mindgame77/regretamin-preview*) ;;
  *) echo "refusing: $PREVIEW_DIR is not the regretamin-preview repo" >&2; exit 1 ;;
esac
git -C "$PREVIEW_DIR" pull --rebase --quiet
export REGRET_NOINDEX=1 SUPABASE_URL=${SUPABASE_URL:-https://sxxgvkdwgiouyqciztec.supabase.co}
if [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  SUPABASE_ANON_KEY=$(python3 -c "import re,sys;print(re.search(r'\"key\": \"([^\"]+)\"',open(sys.argv[1]).read()).group(1))" "$PREVIEW_DIR/index.html")
  export SUPABASE_ANON_KEY
fi
# Static host: there is no Pages Function here. A lab-only tree would remove the other firm pages.
if [ "${LAB_ONLY:-1}" != "0" ]; then
  echo "refusing: this preview is static files only. A lab-only build would remove the other firm pages. LAB_ONLY=0 is the manual rollout." >&2
  exit 1
fi
python3 "$REPO/launch/build.py"
find "$PREVIEW_DIR" -mindepth 1 -maxdepth 1 ! -name .git ! -name .nojekyll -exec rm -rf {} +
cp -a "$REPO/site-launch/." "$PREVIEW_DIR/"
touch "$PREVIEW_DIR/.nojekyll"
cd "$PREVIEW_DIR"
git add -A -- .
if git diff --cached --quiet; then echo "preview already up to date"; exit 0; fi
git commit --quiet -m "Preview: build of regrettamine $(git -C "$REPO" rev-parse --short HEAD) ($(git -C "$REPO" rev-parse --abbrev-ref HEAD))"
git push --quiet origin HEAD
echo "pushed $(git rev-parse --short HEAD) at $(date '+%Y-%m-%d %H:%M %Z'); live in ~1 min at https://mindgame77.github.io/regretamin-preview/"
