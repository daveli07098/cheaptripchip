#!/usr/bin/env bash
# Bump the build number in pubspec.yaml (1.0.0+N → 1.0.0+N+1, shown as
# v1.0.0.N+1), optionally commit, and optionally build + install a release
# on whatever device is connected.
#
#   scripts/bump-build.sh              bump + commit "chore: bump version (vX)"
#   scripts/bump-build.sh --no-commit  bump + stage pubspec.yaml only
#   scripts/bump-build.sh --build      bump + commit + build + install
#   scripts/bump-build.sh --build-only build + install the current HEAD, no bump
#   add --no-web to either build mode to skip the web deploy
#
# The build always uses the committed HEAD: if the working tree has other
# uncommitted edits (e.g. work in progress), it builds from a temporary
# git worktree so those edits never end up on the device.
#
# Every build also copies the Android APK to ~/Downloads/cheaptripchip-v<X>.apk
# for sharing, and builds + deploys the web app from the same source dir and
# commit via scripts/deploy-web.sh (https://cheaptripchip.vercel.app).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

commit=true
build=false
bump=true
web=true
for arg in "$@"; do
  case "$arg" in
    --no-commit) commit=false ;;
    --build) build=true ;;
    --build-only) build=true; bump=false; commit=false ;;
    --no-web) web=false ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
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
build_time="$(date '+%Y-%m-%d %H:%M')"
defines=(--dart-define=GIT_SHA="$sha" --dart-define=BUILD_TIME="$build_time")
repo="$PWD"
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
version="v${semver}.${buildno}"
install_result="not installed"
apk_copy="none"
web_result="skipped (--no-web)"
if [[ "$platform" == ios ]]; then
  "${flutter[@]}" install --release -d "$device_id" "${defines[@]}"
  install_result="installed on iOS device $device_id"
else
  "${flutter[@]}" build apk --release "${defines[@]}"
  apk=build/app/outputs/flutter-apk/app-release.apk
  apk_copy="$HOME/Downloads/cheaptripchip-${version}.apk"
  cp "$apk" "$apk_copy"
  if [[ -n "$device_id" ]]; then
    "$adb" -s "$device_id" install -r -d "$apk"
    install_result="installed on $device_id"
    echo "Installed $version ($sha) on $device_id"
  else
    install_result="no device connected (APK built only)"
    echo "No device connected — built $apk only"
  fi
fi

if $web; then
  # Same source dir (the temp worktree when HEAD is built from one, with
  # env/dev.json already copied in) and the same GIT_SHA/BUILD_TIME label.
  if GIT_SHA="$sha" BUILD_TIME="$build_time" \
      "$repo/scripts/deploy-web.sh" --no-clean --src "$src"; then
    web_result="https://cheaptripchip.vercel.app"
  else
    web_result="FAILED (see output above)"
  fi
fi

echo
echo "Version: $version"
echo "Commit:  $sha"
echo "Device:  $install_result"
echo "APK:     $apk_copy"
echo "Web:     $web_result"
