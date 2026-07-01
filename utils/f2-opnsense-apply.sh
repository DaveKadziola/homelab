#!/usr/bin/env bash
# Apply homelab v2 F2 changes on OPNsense via SSH (interactive password or key auth).
#
# Usage:
#   OPNSENSE_HOST=192.168.1.1 ./utils/f2-opnsense-apply.sh
#   ./utils/f2-opnsense-apply.sh --backup-only
#
# Steps: remote config backup → F2-03 NFS firewall → local config.xml copy (F2-06).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${OPNSENSE_HOST:-192.168.1.1}"
USER="${OPNSENSE_USER:-root}"
SSH_OPTS="${OPNSENSE_SSH_OPTS:--o StrictHostKeyChecking=accept-new}"
REMOTE="${REPO_ROOT}/utils/f2-opnsense-apply-remote.sh"

backup_only=false
if [[ "${1:-}" == "--backup-only" ]]; then
  backup_only=true
fi

run_ssh() {
  ssh ${SSH_OPTS} "${USER}@${HOST}" "$@"
}

echo "=== OPNsense F2 apply @ ${USER}@${HOST} ==="

if [[ "$backup_only" == true ]]; then
  OPNSENSE_HOST="$HOST" OPNSENSE_USER="$USER" "${REPO_ROOT}/utils/backup-opnsense-config.sh"
  exit 0
fi

echo "1/2 Remote: backup + NFS firewall (F2-03)..."
run_ssh 'sh -s' < "$REMOTE"

echo "2/2 Local backup (F2-06)..."
OPNSENSE_HOST="$HOST" OPNSENSE_USER="$USER" "${REPO_ROOT}/utils/backup-opnsense-config.sh"

echo "Done. Update docs/opnsense-baseline.md F2-03/F2-06 checkboxes after verify."
