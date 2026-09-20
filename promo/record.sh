#!/usr/bin/env bash
# record.sh <name> <seconds>  — records the booted simulator screen to promo/raw/<name>.mp4
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
