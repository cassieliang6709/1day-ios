#!/bin/bash
# App Store screenshot capture for 1Day, one language per run.
#
#   ./capture.sh chinese zh-Hans
#   ./capture.sh english en-US
#
# Needs a booted iPhone 17 Pro Max simulator (1320×2868 = the 6.9-inch slot)
# and the idb client, because this machine's Xcode ships no Simulator.app —
# there is no window to click, so taps have to go through CoreSimulator:
#
#   brew install facebook/fb/idb-companion
#   python3.12 -m venv /tmp/idbvenv && /tmp/idbvenv/bin/pip install fb-idb
#
# fb-idb is broken on Python 3.14 (`asyncio.get_event_loop()` raises once no
# loop is running), hence the pinned 3.12 venv.
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

# Tap the centre of the first element whose AXUniqueId or AXLabel contains $1.
# Matching on the tree rather than on fixed points keeps the English run
# working when a translated label changes a row's width.
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
  # shellcheck disable=SC2086
  "$IDB" ui tap --udid "$SIM" $pt
}

launch() { xcrun simctl launch --terminate-running-process "$SIM" "$BUNDLE" "$@" >/dev/null; }

echo "== $OUT_DIR on $SIM"

# A story left over from a previous run turns the empty home state into a card
# and changes which screens are reachable, so start from a clean container.
xcrun simctl uninstall "$SIM" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl install "$SIM" "$APP" >/dev/null

# 01 — onboarding hero. No `-onboarding.completed.v1`: this screen states the
# 3-moments-to-1-film promise and plays the sample film, and it is the only
# place either appears.
launch -appLanguage "$LANG_ARG"
shot 01-hero.png 8

# 03 before 02: the poster grid is what "no story yet" leads to, and tapping a
# poster is what creates the story that 02 needs.
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
