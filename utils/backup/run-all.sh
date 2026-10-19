#!/usr/bin/env bash
# Nightly orchestrator (F5). Safe to run by hand. rclone/HA/vzdump/OPNsense
# skip when the target is missing — they must not fail the timer on DEV.
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

echo "=== homelab backup env=${HOMELAB_ENV} $(date -Is) ==="
"$DIR/pg-dump.sh"
"$DIR/volumes.sh"
"$DIR/repo-zip.sh" || true
"$DIR/opnsense.sh" || true
"$DIR/ha-pull.sh" || true
"$DIR/vzdump.sh" || true
"$DIR/rclone-offsite.sh" || true
echo "=== done ==="
