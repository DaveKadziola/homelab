#!/usr/bin/env bash
# Nightly backup streams that run on the NAS (F5): it shares the IOT subnet with Home Assistant and
# the router, so they need no firewall rule, and it writes straight to the backup disk. The apps host
# keeps pg_dump, volumes, repo-zip and offsite (run-all.sh). Streams that miss their target or
# secret skip with exit 0; a real failure makes the unit fail, and check-fresh.py reports the gap.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENVIRONMENT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENVIRONMENT="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done
export HOMELAB_ENV="${ENVIRONMENT:-${HOMELAB_ENV:?--env required}}"

echo "=== homelab NAS backup env=${HOMELAB_ENV} $(date -Is) ==="
rc=0
for stream in ha-pull ha-yaml opnsense; do
  "$DIR/$stream.sh" || { echo "$stream: FAILED" >&2; rc=1; }
done
echo "=== done (rc=$rc) ==="
exit "$rc"
