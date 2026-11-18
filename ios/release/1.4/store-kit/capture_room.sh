#!/bin/bash
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

launch
expect "home-room-demo"
tap "home-room-demo"
expect "$TITLE"
shot 07-room.png 3

tap "$FILM_NEEDLE"
if expect "6 of 6" || expect "6/6"; then
  shot 09-stitching.png 1
else
  echo "  ·· no stitching screen this run (film already built) — 09 left as is"
fi

expect "play.fill"
tap "play.fill"
shot 08-together.png 2

echo "== done"
for f in "$DEST"/0[789]-*.png; do
  printf '%s  %s\n' "$(sips -g pixelWidth -g pixelHeight "$f" | tail -2 | tr -d ' \n')" "$(basename "$f")"
done
