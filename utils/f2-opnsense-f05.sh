#!/usr/bin/env bash
# F2-05: grocery ACME cert + enable HAProxy on OPNsense via SSH.
#
# Usage: OPNSENSE_HOST=192.168.1.1 ./utils/f2-opnsense-f05.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${OPNSENSE_HOST:-192.168.1.1}"
USER="${OPNSENSE_USER:-root}"
SSH_OPTS="${OPNSENSE_SSH_OPTS:--o StrictHostKeyChecking=accept-new}"
REMOTE="${REPO_ROOT}/utils/f2-opnsense-f05-remote.sh"

echo "=== F2-05 @ ${USER}@${HOST} ==="
ssh ${SSH_OPTS} "${USER}@${HOST}" 'sh -s' < "$REMOTE"
echo "Local backup..."
OPNSENSE_HOST="$HOST" OPNSENSE_USER="$USER" bash "${REPO_ROOT}/utils/backup-opnsense-config.sh"
