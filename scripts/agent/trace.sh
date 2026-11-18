#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

template="Time Profiler" seconds=15 url="" launch=0 top=25
while [[ $# -gt 0 ]]; do
  case "$1" in
    --template) template="$2"; shift 2 ;;
    --seconds) seconds="$2"; shift 2 ;;
    --url) url="$2"; shift 2 ;;
    --launch) launch=1; shift ;;
    --top) top="$2"; shift 2 ;;
    --device) ONEDAY_DEVICE=1; shift ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) die "unknown option $1" ;;
  esac
done

if [[ "${ONEDAY_DEVICE:-0}" == 1 ]]; then udid=$(device_udid); else udid=$(sim_udid); fi
out="$OUT_DIR/$(echo "$template" | tr ' ' '-')-$(date +%Y%m%d-%H%M%S).trace"

if [[ $launch == 1 ]]; then
  if [[ "${ONEDAY_DEVICE:-0}" == 1 ]]; then
    target=(--launch -- "$BUNDLE_ID")
  else
    app=$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" app) || die "app not installed on $udid"
    xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
    target=(--launch -- "$app")
  fi
else
  if [[ "${ONEDAY_DEVICE:-0}" == 1 ]]; then
    json="$OUT_DIR/launch-$$.json"
    xcrun devicectl device process launch --device "$udid" --json-output "$json" "$BUNDLE_ID" >/dev/null
    pid=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"]["process"]["processIdentifier"])' "$json")
  else
    pid=$(xcrun simctl launch "$udid" "$BUNDLE_ID" | awk -F': ' '{print $2}')
  fi
  [[ -n "$pid" ]] || die "could not start $BUNDLE_ID"
  sleep 1
  target=(--attach "$pid")
fi

if [[ -n "$url" ]]; then
  ( sleep 2; open_link "$url"; echo "opened $url" >&2 ) &
fi

echo "recording $template for ${seconds}s → $out" >&2
xcrun xctrace record --template "$template" --device "$udid" --time-limit "${seconds}s" \
  --output "$out" --no-prompt "${target[@]}" >&2

echo "trace: $out"
if [[ "$template" == "Time Profiler" ]]; then
  xml="${out%.trace}.xml"
  xcrun xctrace export --input "$out" \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' > "$xml"
  python3 -I "$(dirname "$0")/trace_summary.py" "$xml" --top "$top"
else
  xcrun xctrace export --input "$out" --toc | grep -Eo 'schema="[^"]+"' | sort -u
  echo "export a table with: xcrun xctrace export --input $out --xpath '/trace-toc/run[@number=\"1\"]/data/table[@schema=\"<schema>\"]'"
fi
