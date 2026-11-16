
BUNDLE_ID="${ONEDAY_BUNDLE_ID:-com.cassie.AISetlog.dev}"
SUBSYSTEM="com.cassie.AISetlog"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${ONEDAY_AGENT_OUT:-/tmp/1day-agent}"
mkdir -p "$OUT_DIR"

die() { echo "error: $*" >&2; exit 1; }

sim_udid() {
  [[ -n "${ONEDAY_UDID:-}" ]] && { echo "$ONEDAY_UDID"; return; }
  local udid
  udid=$(xcrun simctl list devices booted | grep -Eo '[0-9A-F-]{36}' | head -1)
  [[ -n "$udid" ]] || die "no booted simulator (boot one, or set ONEDAY_UDID)"
  echo "$udid"
}

device_udid() {
  [[ -n "${ONEDAY_UDID:-}" ]] && { echo "$ONEDAY_UDID"; return; }
  local udid
  udid=$(xcrun devicectl list devices 2>/dev/null \
    | grep -E 'available \(paired\).*physical' | grep -Eo '[0-9A-F]{8}-[0-9A-F]{16}' | head -1)
  [[ -n "$udid" ]] || die "no paired iPhone available (unlock it, or set ONEDAY_UDID)"
  echo "$udid"
}

with_timeout() {
  local secs="$1"; shift
  "$@" &
  local pid=$!
  ( sleep "$secs"; kill -INT "$pid" 2>/dev/null; sleep 2; kill -9 "$pid" 2>/dev/null ) &
  local watchdog=$!
  wait "$pid" 2>/dev/null
  local status=$?
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  return $status
}

open_link() {
  local path="${1#oneday://debug/}"
  if [[ "${ONEDAY_DEVICE:-0}" == 1 ]]; then
    xcrun devicectl device process launch --device "$(device_udid)" \
      --payload-url "oneday://debug/$path" "$BUNDLE_ID" >/dev/null
  else
    local udid data
    udid=$(sim_udid)
    data=$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data) || die "$BUNDLE_ID not installed"
    mkdir -p "$data/Library/Caches"
    echo "$path" >> "$data/Library/Caches/debug-link.txt"
    xcrun simctl spawn "$udid" notifyutil -p com.cassie.AISetlog.debug.link
  fi
}
