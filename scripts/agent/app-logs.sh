#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

seconds=20 last="" category="" url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --seconds) seconds="$2"; shift 2 ;;
    --last) last="$2"; shift 2 ;;
    --category) category="$2"; shift 2 ;;
    --url) url="$2"; shift 2 ;;
    --device) ONEDAY_DEVICE=1; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) die "unknown option $1" ;;
  esac
done

predicate="subsystem == \"$SUBSYSTEM\""
[[ -n "$category" ]] && predicate="$predicate AND category == \"$category\""

if [[ "${ONEDAY_DEVICE:-0}" == 1 ]]; then
  udid=$(device_udid)
  archive="$OUT_DIR/device-$(date +%s).logarchive"
  sudo -n log collect --device-udid "$udid" --last "${last:-10m}" --output "$archive" >/dev/null \
    || die "log collect needs sudo (run it in a terminal yourself), or use phone_logs from iphone-use"
  log show --archive "$archive" --style compact --info --debug --predicate "$predicate"
  exit 0
fi

udid=$(sim_udid)
if [[ -n "$last" ]]; then
  xcrun simctl spawn "$udid" log show --last "$last" --style compact --info --debug \
    --predicate "$predicate"
  exit 0
fi

if [[ -n "$url" ]]; then
  ( sleep 1; open_link "$url" ) &
fi
with_timeout "$seconds" xcrun simctl spawn "$udid" log stream --style compact --level debug \
  --predicate "$predicate" || true
