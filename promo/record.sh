#!/usr/bin/env bash
set -euo pipefail
NAME="${1:?name}"; SECS="${2:-10}"
OUT="$(cd "$(dirname "$0")" && pwd)/raw/${NAME}.mp4"
rm -f "$OUT"
xcrun simctl io booted recordVideo --codec h264 --force "$OUT" &
PID=$!
sleep "$SECS"
kill -INT $PID
wait $PID 2>/dev/null || true
echo "saved $OUT"
