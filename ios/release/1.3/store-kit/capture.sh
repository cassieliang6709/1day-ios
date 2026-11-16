#!/bin/bash
set -euo pipefail

LANG_ARG="${1:-chinese}"
OUT_DIR="${2:-zh-Hans}"
SIM="${SIM_UDID:-$(xcrun simctl list devices | awk '/1day-shots/ {print $2}' | tr -d '()')}"
IDB="${IDB_BIN:-/tmp/idbvenv/bin/idb}"
APP="${APP_PATH:-/tmp/1day-dd/Build/Products/Debug-iphonesimulator/AISetlog.app}"
BUNDLE=com.cassie.AISetlog
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HERE/$OUT_DIR"

mkdir -p "$DEST"
"$IDB" connect "$SIM" >/dev/null 2>&1 || true

shot() { sleep "${2:-4}"; xcrun simctl io "$SIM" screenshot "$DEST/$1" >/dev/null 2>&1; echo "  → $1"; }

tap() {
  local needle="$1"
  local pt
  pt=$("$IDB" ui describe-all --udid "$SIM" 2>/dev/null | python3 -c '
import json,sys
needle=sys.argv[1].lower()
for e in json.load(sys.stdin):
    hay=((e.get("AXUniqueId") or "")+" "+(e.get("AXLabel") or "")).lower()
    if needle in hay:
        f=e["frame"]; print(int(f["x"]+f["width"]/2), int(f["y"]+f["height"]/2)); break
' "$needle")
  [ -z "$pt" ] && { echo "  !! no element matching '$needle'"; return 1; }
  "$IDB" ui tap --udid "$SIM" $pt
}

launch() { xcrun simctl launch --terminate-running-process "$SIM" "$BUNDLE" "$@" >/dev/null; }

echo "== $OUT_DIR on $SIM"

xcrun simctl uninstall "$SIM" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl install "$SIM" "$APP" >/dev/null

launch -appLanguage "$LANG_ARG"
shot 01-hero.png 8

launch -onboarding.completed.v1 YES -appLanguage "$LANG_ARG"
sleep 8
tap "开始今天的故事" 2>/dev/null || tap "today"
shot 03-themes.png 5

tap "完美的一天" 2>/dev/null || tap "perfect"
shot 04-moments.png 6

tap "room-back"
shot 02-home.png 5

echo "== done"
for f in "$DEST"/*.png; do
  printf '%s  %s\n' "$(sips -g pixelWidth -g pixelHeight "$f" | tail -2 | tr -d ' \n')" "$(basename "$f")"
done
