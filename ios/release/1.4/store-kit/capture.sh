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

tree() { "$IDB" ui describe-all --udid "$SIM" 2>/dev/null; }

shot() { sleep "${2:-4}"; xcrun simctl io "$SIM" screenshot "$DEST/$1" >/dev/null 2>&1; echo "  → $1"; }

tap() {
  local needle="$1" pt
  pt=$(tree | python3 -c '
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

expect() {
  local needle="$1" n=0
  until tree | python3 -c '
import json,sys
needle=sys.argv[1].lower()
sys.exit(0 if any(needle in ((e.get("AXUniqueId") or "")+" "+(e.get("AXLabel") or "")).lower()
                  for e in json.load(sys.stdin)) else 1)
' "$needle"; do
    n=$((n+1))
    [ "$n" -gt 10 ] && { echo "  !! never reached a screen containing '$needle'"; return 1; }
    sleep 1
  done
}

launch() { xcrun simctl launch --terminate-running-process "$SIM" "$BUNDLE" "$@" >/dev/null; }

echo "== $OUT_DIR on $SIM"

xcrun simctl uninstall "$SIM" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl install "$SIM" "$APP" >/dev/null

launch -appLanguage "$LANG_ARG"
sleep 8
shot 01-hero.png 2

launch -onboarding.completed.v1 YES -appLanguage "$LANG_ARG"
expect "start today" || expect "开始今天"
shot 02-home.png 3

tap "start today" || tap "开始今天"
expect "what will today" || expect "今天会是什么"
shot 03-themes.png 4

tap "perfect day" || tap "完美的一天"
expect "start filming" || expect "开始拍"
shot 04-setup.png 4

tap "start filming" || tap "开始拍"
expect "wake up" || expect "起床"
shot 05-timeline.png 5

xcrun simctl terminate "$SIM" "$BUNDLE" >/dev/null 2>&1 || true
python3 "$HERE/seed_film.py" "$SIM" "$([ "$LANG_ARG" = chinese ] && echo zh || echo en)" >/dev/null
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || true
sleep 5
"$IDB" connect "$SIM" >/dev/null 2>&1 || true
launch -onboarding.completed.v1 YES -appLanguage "$LANG_ARG"
expect "film ready" || expect "影片完成"
tap "film ready" || tap "影片完成"
expect "7/7" || expect "7 / 7"
shot 06-film.png 6

echo "== done"
for f in "$DEST"/*.png; do
  printf '%s  %s\n' "$(sips -g pixelWidth -g pixelHeight "$f" | tail -2 | tr -d ' \n')" "$(basename "$f")"
done
