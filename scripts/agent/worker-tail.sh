#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

seconds=20 extra=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --seconds) seconds="$2"; shift 2 ;;
    --errors) extra+=(--status error); shift ;;
    --search) extra+=(--search "$2"); shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) die "unknown option $1" ;;
  esac
done

cd "$REPO_ROOT/workers/api"
with_timeout "$seconds" bash -c '
  npx --yes wrangler tail oneday-api --format json "$@" 2>/dev/null \
  | jq -rc --unbuffered "
      (.event.request.method // \"\") as \$m
      | (.event.request.url // \"\" | sub(\"^https?://[^/]+\"; \"\") | sub(\"\\\\?.*\"; \"\")) as \$p
      | (.event.response.status // \"-\") as \$s
      | (.logs[]? | \"\(.level) \(.message | map(tostring) | join(\" \"))\"),
        (.exceptions[]? | \"EXCEPTION \(.name): \(.message)\"),
        (if (.logs | length) == 0 then \"\(\$m) \(\$p) \(\$s) \(.outcome)\" else empty end)"
' _ "${extra[@]+"${extra[@]}"}" || true
