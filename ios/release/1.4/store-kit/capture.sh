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
#
# The 1.3 version of this script tapped 开始今天的故事 and 完美的一天 and fell
# back to the English "perfect". Both needles were gone by 1.4 — the home
# screen is the 我的 tab now and its button is 开始今天的故事 only in the empty
# state — and a missed tap does not stop the run, it just shoots whatever
# screen is still up. So every tap here is checked: `tap` fails the script if
# nothing matched, and `expect` fails it if the screen that followed is not
# the one the next shot is supposed to be of. A short run that stops is worth
# more than five files of the wrong screen.
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

# Centre of the first element whose AXUniqueId or AXLabel contains $1.
# Matching on the tree rather than on fixed points keeps the English run
# working when a translated label changes a row's width.
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
  # shellcheck disable=SC2086
  "$IDB" ui tap --udid "$SIM" $pt
}

# Refuse to photograph the wrong screen. Called before each shot with a string
# that only the intended screen shows.
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

# A story left over from a previous run turns the empty home state into a card
# and changes which screens are reachable, so start from a clean container.
xcrun simctl uninstall "$SIM" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl install "$SIM" "$APP" >/dev/null

# 01 — onboarding hero. No `-onboarding.completed.v1`: this screen states the
# 3-moments-to-1-film promise and plays the sample film, and it is the only
# place either appears.
launch -appLanguage "$LANG_ARG"
sleep 8
shot 01-hero.png 2

# 02 — home, empty. The one screen that shows the three tabs, which is the
# single biggest difference between the 1.3 kit and the shipping app.
launch -onboarding.completed.v1 YES -appLanguage "$LANG_ARG"
expect "start today" || expect "开始今天"
shot 02-home.png 3

# 03 — the poster rack, which is what "no story yet" leads to.
#
# Expect on the page title, not on a shelf name: the shelves are 1-Day / 7-Day
# and the 1.3 script's "one day" never matched anything.
tap "start today" || tap "开始今天"
expect "what will today" || expect "今天会是什么"
shot 03-themes.png 4

# 04 — the settings page a poster opens: moments, who's filming, clip length,
# frame. Every decision on one page.
tap "perfect day" || tap "完美的一天"
expect "start filming" || expect "开始拍"
shot 04-setup.png 4

# 05 — the timeline the story starts on. Expect the first moment's name: the
# progress line reads "0 of 7 filmed" in English and 0/7 in Chinese, so there
# is no shared substring to wait on.
tap "start filming" || tap "开始拍"
expect "wake up" || expect "起床"
shot 05-timeline.png 5

# 06 — the finished film, which is the shot that sells the app and the one the
# simulator cannot film: the fake camera writes colour bars. `seed_film.py`
# fills the story this run just created with real footage cut from the
# onboarding sample. It has to run with the app closed (the write goes through
# `defaults`, and a live app's cfprefsd would overwrite it), and it has to run
# *after* the capture above, because the story it fills is the one the poster
# tap made — seeding first and capturing second would put a Chinese story
# title in the English set.
#
# seed_film.py reboots the simulator on its way out — that is how it makes
# cfprefsd drop the copy of the preferences it is holding. So everything below
# has to wait the device out and reconnect idb; a `sleep` and a launch on the
# old connection land on a device that is still booting and do nothing.
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
