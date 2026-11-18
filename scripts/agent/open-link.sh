#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
[[ "${1:-}" == "--device" ]] && { ONEDAY_DEVICE=1; shift; }
[[ $# -ge 1 && "$1" != -h && "$1" != --help ]] || { sed -n '2,11p' "$0"; exit 0; }
for path in "$@"; do open_link "$path"; done
