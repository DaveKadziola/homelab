#!/usr/bin/env bash
# Download OPNsense config.xml via SSH (one-shot backup).
#
# Usage:
#   OPNSENSE_HOST=192.168.20.1 OPNSENSE_USER=root ./utils/backup-opnsense-config.sh
#
# Requires: SSH key auth to OPNsense (password auth works but not recommended).
# Output: opnsense/backups/config-YYYYMMDD-HHMMSS.xml

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="${REPO_ROOT}/opnsense/backups"
HOST="${OPNSENSE_HOST:-192.168.20.1}"
USER="${OPNSENSE_USER:-root}"
SSH_OPTS="${OPNSENSE_SSH_OPTS:--o StrictHostKeyChecking=accept-new}"

STAMP=$(date +%Y%m%d-%H%M%S)
OUT="${BACKUP_DIR}/config-${STAMP}.xml"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

echo "Backing up OPNsense config from ${USER}@${HOST}..."

# OPNsense stores config at /conf/config.xml
scp ${SSH_OPTS} "${USER}@${HOST}:/conf/config.xml" "$OUT"

chmod 600 "$OUT"
echo "Saved: ${OUT}"
echo "Copy to Bitwarden note / offsite (F5) — do not commit to git."
