#!/usr/bin/env bash
set -euo pipefail
BUNDLE="com.cassie.AISetlog"
HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="$(xcrun simctl get_app_container booted "$BUNDLE" data)"
DEST="$DATA/Documents/demo-clips"
rm -rf "$DEST"; mkdir -p "$DEST"
for f in "$HERE"/out/demo/demo-clip-*.mp4; do
  n="$(basename "$f" .mp4)"; n="${n##*-}"
  cp "$f" "$DEST/$n.mp4"
done
ls -1 "$DEST"
echo "staged into $DEST"
