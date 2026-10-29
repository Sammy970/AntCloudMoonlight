#!/usr/bin/env bash
# Rebuilds AntCloud with a fresh signing profile and installs it on your iPhone.
#
# Free Apple ID builds stop opening 7 days after their provisioning profile was created, and a plain
# rebuild reuses the cached profile (same expiry). This moves the cached profile aside so Xcode asks
# Apple for a new one, which restarts the 7 days, then installs over Wi-Fi or USB. Your data is kept.
#
# Usage: scripts/renew-and-install.sh [--skip-renew] [--integrate]
#   --skip-renew   keep the current profile (just rebuild and install)
#   --integrate    re-run integrate-moonlight.rb first (after pulling changes to this repo)
#
# Settings come from scripts/renew.env (not committed; copy renew.env.example) or the environment:
#   TEAM_ID     your Apple team ID (Xcode → Settings → Accounts)
#   BUNDLE_ID   the bundle ID you build with, e.g. com.yourname.moonlight
#   DEVICE      optional device name or identifier; defaults to the first available iPhone
#   MOONLIGHT   optional path to the moonlight-ios checkout; defaults to ../moonlight-ios
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "$here/scripts/renew.env" ]] && source "$here/scripts/renew.env"

renew=1
integrate=0
for arg in "$@"; do
  case "$arg" in
    --skip-renew) renew=0 ;;
    --integrate) integrate=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

: "${TEAM_ID:?Set TEAM_ID in scripts/renew.env (see renew.env.example)}"
: "${BUNDLE_ID:?Set BUNDLE_ID in scripts/renew.env (see renew.env.example)}"
MOONLIGHT="${MOONLIGHT:-$here/../moonlight-ios}"
[[ -d "$MOONLIGHT" ]] || { echo "moonlight-ios not found at $MOONLIGHT" >&2; exit 1; }

# xcode-select may point at the Command Line Tools; the build needs full Xcode.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  export DEVELOPER_DIR="$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1)/Contents/Developer"
fi
[[ -d "$DEVELOPER_DIR" ]] || { echo "Xcode not found in /Applications" >&2; exit 1; }

step() { printf '\n\033[1;34m▸ %s\033[0m\n' "$*"; }

# 1. Find the iPhone.
step "Looking for your iPhone"
devices_json="$(mktemp)"
trap 'rm -f "$devices_json"' EXIT
xcrun devicectl list devices --json-output "$devices_json" >/dev/null 2>&1
device="$(python3 - "$devices_json" "${DEVICE:-}" <<'PY'
import json, sys
wanted = sys.argv[2].lower()
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    props, hw = d.get("deviceProperties", {}), d.get("hardwareProperties", {})
    if hw.get("reality") != "physical" or hw.get("platform") != "iOS":
        continue
    name, ident, udid = props.get("name", ""), d.get("identifier", ""), hw.get("udid", "")
    if wanted and wanted not in (name.lower(), ident.lower(), udid.lower()):
        continue
    if d.get("connectionProperties", {}).get("tunnelState") == "unavailable":
        continue
    print(f"{udid or ident}\t{name}")
    break
PY
)"
[[ -n "$device" ]] || { echo "No iPhone found. Unlock it and keep it on the same Wi-Fi as this Mac (or plug it in)." >&2; exit 1; }
device_id="${device%%$'\t'*}"
echo "Using ${device#*$'\t'}"

# 2. Move the cached profile aside so Xcode requests a new 7-day one.
profiles="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
if (( renew )) && [[ -d "$profiles" ]]; then
  step "Retiring the cached signing profile for $BUNDLE_ID"
  backup="$HOME/Library/Caches/AntCloud/old-profiles"
  mkdir -p "$backup"
  moved=0
  for f in "$profiles"/*.mobileprovision; do
    [[ -e "$f" ]] || continue
    app_id="$(security cms -D -i "$f" 2>/dev/null | plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null || true)"
    if [[ "$app_id" == "$TEAM_ID.$BUNDLE_ID" ]]; then
      mv "$f" "$backup/"
      moved=$((moved + 1))
    fi
  done
  echo "Moved $moved profile(s) to $backup"
fi

# 3. Optionally re-integrate, then build.
if (( integrate )); then
  step "Integrating AntCloud into Moonlight"
  ruby "$here/integrate-moonlight.rb" "$MOONLIGHT"
fi

step "Building (this takes a minute or two)"
log="$(mktemp)"
if ! xcodebuild -project "$MOONLIGHT/Moonlight.xcodeproj" -scheme Moonlight -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath "$MOONLIGHT/build" -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" build >"$log" 2>&1; then
  grep -E "error:" "$log" | head -20 >&2
  echo "Build failed. Full log: $log" >&2
  exit 1
fi
rm -f "$log"
app="$MOONLIGHT/build/Build/Products/Debug-iphoneos/Moonlight.app"

# 4. Install.
step "Installing on your iPhone"
xcrun devicectl device install app --device "$device_id" "$app" >/dev/null

expiry="$(security cms -D -i "$app/embedded.mobileprovision" | plutil -extract ExpirationDate raw -o - -)"
# The profile's date is UTC; show it in local time.
expiry_epoch="$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$expiry" +%s 2>/dev/null || true)"
expiry_local="$([[ -n "$expiry_epoch" ]] && date -r "$expiry_epoch" "+%a %d %b, %I:%M %p" || echo "$expiry")"
printf '\n\033[1;32m✓ Installed. AntCloud now runs until %s.\033[0m\n' "$expiry_local"
