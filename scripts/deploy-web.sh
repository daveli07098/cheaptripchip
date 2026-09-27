#!/usr/bin/env bash
# Build the Flutter web app and deploy it to Vercel (project "cheaptripchip",
# production URL https://cheaptripchip.vercel.app). iPhone users open that URL
# in Safari and use Share → Add to Home Screen.
#
#   scripts/deploy-web.sh               clean build + production deploy
#   scripts/deploy-web.sh --no-clean    skip `flutter clean` (faster rebuilds)
#   scripts/deploy-web.sh --src DIR     build from DIR (e.g. the temp worktree
#                                       scripts/bump-build.sh builds HEAD in)
#
# GIT_SHA / BUILD_TIME in the environment override the version label's
# defaults (HEAD of the source dir / now), so a combined Android + web build
# shows the same values on both.
#
# Needs env/dev.json (GEMINI_API_KEY = the proxy's APP_TOKEN, GEMINI_BASE_URL
# = the proxy) and a logged-in Vercel CLI. The build embeds GEMINI_API_KEY,
# so it must never be the raw Google key — the script refuses unless
# GEMINI_BASE_URL points at a proxy. web_deploy/vercel.json (SPA rewrite,
# caching, Firebase /__/auth proxy) is copied into build/web before deploy.
set -euo pipefail

VERCEL_PROJECT=cheaptripchip
WEB_URL=https://cheaptripchip.vercel.app
# Deploy config comes from this script's checkout, so an older --src commit
# (from before web_deploy/ existed) still deploys with the current config.
vercel_config="$(cd "$(dirname "$0")/.." && pwd)/web_deploy/vercel.json"

clean=true
src=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-clean) clean=false ;;
    --src) src="${2:?--src needs a directory}"; shift ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

cd "${src:-$(git rev-parse --show-toplevel)}"

if [[ ! -f env/dev.json ]]; then
  echo "env/dev.json missing — copy env/dev.example.json first" >&2
  exit 1
fi
base_url=$(python3 -c 'import json;print(json.load(open("env/dev.json")).get("GEMINI_BASE_URL",""))')
if [[ "$base_url" != https://* ]]; then
  echo "GEMINI_BASE_URL must point at the Gemini proxy for a public web build" >&2
  exit 1
fi

if $clean; then
  flutter clean
fi
flutter build web --release \
  --dart-define-from-file=env/dev.json \
  --dart-define=GIT_SHA="${GIT_SHA:-$(git rev-parse --short HEAD)}" \
  --dart-define=BUILD_TIME="${BUILD_TIME:-$(date '+%Y-%m-%d %H:%M')}"

cp "$vercel_config" build/web/vercel.json
# `flutter clean` wipes build/web/.vercel, so re-link every run.
npx --yes vercel link --yes --project "$VERCEL_PROJECT" --cwd build/web >/dev/null
npx --yes vercel deploy --prod --yes --cwd build/web >/dev/null
echo "Deployed web app: $WEB_URL"
