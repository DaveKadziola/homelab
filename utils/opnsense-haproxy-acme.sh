#!/usr/bin/env bash
# Grocery ACME cert + enable HAProxy on OPNsense via SSH.
#
# Usage: OPNSENSE_HOST=192.168.1.1 ./utils/opnsense-haproxy-acme.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${OPNSENSE_HOST:-192.168.1.1}"
USER="${OPNSENSE_USER:-root}"
SSH_OPTS="${OPNSENSE_SSH_OPTS:--o StrictHostKeyChecking=accept-new}"
REMOTE="${REPO_ROOT}/utils/opnsense-haproxy-acme-remote.sh"

echo "=== HAProxy ACME @ ${USER}@${HOST} ==="
ssh ${SSH_OPTS} "${USER}@${HOST}" 'sh -s' < "$REMOTE"
echo "Local backup..."
OPNSENSE_HOST="$HOST" OPNSENSE_USER="$USER" bash "${REPO_ROOT}/utils/backup-opnsense-config.sh"
