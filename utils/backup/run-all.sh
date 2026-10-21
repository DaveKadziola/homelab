#!/usr/bin/env bash
# Nightly orchestrator on the apps host (F5). Safe to run by hand. Home Assistant and OPNsense run on
# the NAS (run-nas.sh), the VM dumps are a Proxmox job (utils/pve-backup-job.py). rclone skips when
# the target is missing — it must not fail the timer on DEV.
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
"$DIR/rclone-offsite.sh" || true
echo "=== done ==="
