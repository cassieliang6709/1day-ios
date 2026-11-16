#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

breaks=() cmds=() url="" hits=1 seconds=60
while [[ $# -gt 0 ]]; do
  case "$1" in
    --break) breaks+=("$2"); shift 2 ;;
    --cmd) cmds+=("$2"); shift 2 ;;
    --url) url="$2"; shift 2 ;;
    --hits) hits="$2"; shift 2 ;;
    --seconds) seconds="$2"; shift 2 ;;
    --device) ONEDAY_DEVICE=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) die "unknown option $1" ;;
  esac
done
[[ ${#cmds[@]} -gt 0 ]] || cmds=("bt 15" "frame variable")

script="$OUT_DIR/debug-$$.lldb"
: > "$script"

if [[ "${ONEDAY_DEVICE:-0}" == 1 ]]; then
  udid=$(device_udid)
  json="$OUT_DIR/launch-$$.json"
  xcrun devicectl device process launch --device "$udid" --terminate-existing \
    --start-stopped --json-output "$json" "$BUNDLE_ID" >/dev/null
  pid=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"]["process"]["processIdentifier"])' "$json")
  {
    echo "device select $udid"
    echo "device process attach --pid $pid"
  } >> "$script"
else
  udid=$(sim_udid)
  pid=$(xcrun simctl launch --wait-for-debugger --terminate-running-process "$udid" "$BUNDLE_ID" \
    | awk -F': ' '{print $2}')
  echo "process attach --pid $pid" >> "$script"
fi
[[ -n "$pid" ]] || die "could not launch $BUNDLE_ID"
echo "launched pid $pid, attaching" >&2

for b in "${breaks[@]+"${breaks[@]}"}"; do
  if [[ "$b" == *.swift:* ]]; then
    echo "breakpoint set --file ${b%%:*} --line ${b##*:}" >> "$script"
  else
    echo "breakpoint set --name $b" >> "$script"
  fi
done
echo "breakpoint list --brief" >> "$script"

for ((i = 1; i <= hits; i++)); do
  echo "continue" >> "$script"
  echo "script print('=== stop $i ===')" >> "$script"
  for c in "${cmds[@]}"; do echo "$c" >> "$script"; done
done
echo "detach" >> "$script"

if [[ -n "$url" ]]; then
  ( sleep 4; open_link "$url"; echo "opened $url" >&2 ) &
fi

with_timeout "$seconds" lldb --batch --source "$script" \
  -k 'script print("=== crashed ===")' -k 'bt 30' -k 'register read pc' || {
  echo "lldb stopped after ${seconds}s or failed; breakpoint may never have been hit" >&2
}
rm -f "$script"
