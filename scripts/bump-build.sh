#!/usr/bin/env bash
# Bump the build number in pubspec.yaml (1.0.0+N → 1.0.0+N+1, shown as
# v1.0.0.N+1), optionally commit, and optionally build + install a release
# on whatever device is connected.
#
#   scripts/bump-build.sh              bump + commit "chore: bump version (vX)"
#   scripts/bump-build.sh --no-commit  bump + stage pubspec.yaml only
#   scripts/bump-build.sh --build      bump + commit + build + install
#   scripts/bump-build.sh --build-only build + install the current HEAD, no bump
#
# The build always uses the committed HEAD: if the working tree has other
# uncommitted edits (e.g. work in progress), it builds from a temporary
# git worktree so those edits never end up on the device.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

commit=true
build=false
bump=true
for arg in "$@"; do
  case "$arg" in
    --no-commit) commit=false ;;
    --build) build=true ;;
    --build-only) build=true; bump=false; commit=false ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [[ -f .fvmrc || -d .fvm ]] && command -v fvm >/dev/null; then
  flutter=(fvm flutter)
else
  flutter=(flutter)
fi
adb="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
command -v adb >/dev/null && adb="$(command -v adb)"

current="$(sed -nE 's/^version: *([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+).*/\1 \2/p' pubspec.yaml)"
[[ -n "$current" ]] || { echo "pubspec.yaml has no 'version: X.Y.Z+N' line" >&2; exit 1; }
read -r semver buildno <<<"$current"

if $bump; then
  buildno=$((buildno + 1))
  sed -i '' -E "s/^version: *[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+/version: ${semver}+${buildno}/" pubspec.yaml
  git add pubspec.yaml
  echo "Bumped to v${semver}.${buildno}"
  if $commit; then
    git commit -q -m "chore: bump version (v${semver}.${buildno})" -- pubspec.yaml
    echo "Committed $(git rev-parse --short HEAD)"
  fi
fi

$build || exit 0

# Pick a device: physical over emulator/simulator, Android or iOS.
device_json="$("${flutter[@]}" devices --machine 2>/dev/null)"
read -r device_id platform < <(python3 - "$device_json" <<'PY'
import json, sys
devices = [d for d in json.loads(sys.argv[1] or "[]")
           if d.get("isSupported", True)
           and (d.get("targetPlatform", "").startswith("android")
                or d.get("targetPlatform", "").startswith("ios"))]
devices.sort(key=lambda d: d.get("emulator", False))
if devices:
    d = devices[0]
    print(d["id"], "ios" if d["targetPlatform"].startswith("ios") else "android")
else:
    print("", "")
PY
)

sha="$(git rev-parse --short HEAD)"
defines=(--dart-define=GIT_SHA="$sha" --dart-define=BUILD_TIME="$(date '+%Y-%m-%d %H:%M')")
[[ -f env/dev.json ]] && defines=(--dart-define-from-file=env/dev.json "${defines[@]}")

src="$PWD"
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  src="$(mktemp -d)/build"
  echo "Working tree has uncommitted edits — building HEAD ($sha) in $src"
  git worktree add --detach -q "$src" HEAD
  trap 'git worktree remove --force "$src"' EXIT
  [[ -f env/dev.json ]] && cp env/dev.json "$src/env/"
fi

cd "$src"
if [[ "$platform" == ios ]]; then
  "${flutter[@]}" install --release -d "$device_id" "${defines[@]}"
else
  "${flutter[@]}" build apk --release "${defines[@]}"
  apk=build/app/outputs/flutter-apk/app-release.apk
  if [[ -n "$device_id" ]]; then
    "$adb" -s "$device_id" install -r -d "$apk"
    echo "Installed v${semver}.${buildno} ($sha) on $device_id"
  else
    echo "No device connected — built $apk only"
  fi
fi
