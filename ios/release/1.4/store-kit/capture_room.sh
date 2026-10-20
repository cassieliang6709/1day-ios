#!/bin/bash
# The three shared-room shots: the room, the stitched film, and the stitching.
#
#   ./capture_room.sh english en-US
#   ./capture_room.sh chinese zh-Hans
#
# Run after capture.sh — it needs the app installed and onboarding done, and
# it writes 07/08/09 into the same set.
#
# Shared rooms normally need two devices on two iCloud accounts, which is why
# this is the one part of the app a screenshot run cannot simply walk to. The
# way in is the demo room: `LocalRoomRuntime` is the *production* room with a
# local sync source under it, so what the camera sees is the real screen and
# the real composition, not a mock.
#
# Two launch arguments make it presentable (see LocalRoomRuntime.swift):
#
#   -demoRoomClips demo-clips   take footage from Documents/demo-clips rather
#                               than generating colour cards
#   -demoRoomChrome NO          drop the local-only notice, the member picker
#                               and the import menu — the scaffolding, not the
#                               room
#
# The second is only safe together with the first: a room with no import menu
# and nowhere to import from is a room stuck with colour bars.
#
# Clip files are handed out moment-major — 1.mp4 is the first member of the
# first moment, 2.mp4 the second member of the same moment — so two members
# across three moments is six files, in order.
set -euo pipefail

LANG_ARG="${1:-chinese}"
OUT_DIR="${2:-zh-Hans}"
SIM="${SIM_UDID:-$(xcrun simctl list devices | awk '/1day-shots/ {print $2}' | tr -d '()')}"
IDB="${IDB_BIN:-/tmp/idbvenv/bin/idb}"
BUNDLE=com.cassie.AISetlog
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HERE/$OUT_DIR"
SOURCE="$(cd "$HERE/../../.." && pwd)/AISetlog/Resources/Onboarding/sample-film.mp4"

if [ "$LANG_ARG" = chinese ]; then
  TITLE="我们的周六"; MEMBERS="小蓝,小白"; MOMENTS="晨光,午饭,傍晚的光"
  FILM_NEEDLE="看成片"
else
  TITLE="Our Saturday"; MEMBERS="Cassie,Mia"; MOMENTS="Morning light,Lunch,Golden hour"
  FILM_NEEDLE="see the film"
fi

mkdir -p "$DEST"
"$IDB" connect "$SIM" >/dev/null 2>&1 || true

tree() { "$IDB" ui describe-all --udid "$SIM" 2>/dev/null; }
shot() { sleep "${2:-3}"; xcrun simctl io "$SIM" screenshot "$DEST/$1" >/dev/null 2>&1; echo "  → $1"; }

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

expect() {
  local needle="$1" n=0
  until tree | python3 -c '
import json,sys
needle=sys.argv[1].lower()
sys.exit(0 if any(needle in ((e.get("AXUniqueId") or "")+" "+(e.get("AXLabel") or "")).lower()
                  for e in json.load(sys.stdin)) else 1)
' "$needle"; do
    n=$((n+1))
    [ "$n" -gt 30 ] && { echo "  !! never reached a screen containing '$needle'"; return 1; }
    sleep 1
  done
}

launch() {
  xcrun simctl launch --terminate-running-process "$SIM" "$BUNDLE" \
    -onboarding.completed.v1 YES -appLanguage "$LANG_ARG" \
    -demoEntries YES -demoRoomTitle "$TITLE" -demoRoomMembers "$MEMBERS" \
    -demoRoomMoments "$MOMENTS" -demoRoomClips demo-clips -demoRoomChrome NO >/dev/null
}

echo "== $OUT_DIR room shots on $SIM"

CONTAINER=$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)
mkdir -p "$CONTAINER/Documents/demo-clips"
i=1
for offset in 0.0 1.6 3.2 4.8 6.4 8.0; do
  ffmpeg -v error -y -ss "$offset" -i "$SOURCE" -t 2 -an \
    -c:v libx264 -pix_fmt yuv420p -preset veryfast \
    "$CONTAINER/Documents/demo-clips/$i.mp4"
  i=$((i + 1))
done

# 07 — the room. Two members, every moment holding both their clips side by
# side, and the film offer once the day is full.
launch
expect "home-room-demo"
tap "home-room-demo"
expect "$TITLE"
shot 07-room.png 3

# 09 before 08: the stitching screen is on its way to the film, and it only
# exists for as long as the stitch takes.
#
# Missing it is not a failure. A container that already holds this room's film
# goes straight to the player, so on a second run in the same container there
# is no stitching screen to photograph — keep whatever the last run produced
# rather than stopping the two shots that come after.
tap "$FILM_NEEDLE"
if expect "6 of 6" || expect "6/6"; then
  shot 09-stitching.png 1
else
  echo "  ·· no stitching screen this run (film already built) — 09 left as is"
fi

# 08 — the finished film, paused two seconds in so the frame has both people
# in it rather than sitting on black.
#
# Wait on the play button itself. Both the page title and "0:06" land in the
# tree a beat before the player's own controls do, so expecting either and
# tapping straight after misses.
expect "play.fill"
tap "play.fill"
shot 08-together.png 2

echo "== done"
for f in "$DEST"/0[789]-*.png; do
  printf '%s  %s\n' "$(sips -g pixelWidth -g pixelHeight "$f" | tail -2 | tr -d ' \n')" "$(basename "$f")"
done
