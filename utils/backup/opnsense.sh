#!/usr/bin/env bash
# Copy OPNsense config.xml into the backup tree (F5). Skips when the router
# is unreachable (nested DEV, or laptop not on the LAN).
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [[ "${HOMELAB_ENV}" != "prod" ]]; then
  echo "opnsense: only on prod — skip"
  exit 0
fi

HOST="${OPNSENSE_HOST:-192.168.20.1}"
USER="${OPNSENSE_USER:-root}"
if ! ping -c 1 -W 2 "$HOST" >/dev/null 2>&1; then
  echo "opnsense: ${HOST} unreachable — skip"
  exit 0
fi

ROOT="$(hl_storage backup_root)/opnsense"
mkdir -p "$ROOT"
dest="${ROOT}/config-$(hl_stamp).xml"
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "${USER}@${HOST}" \
  'cat /conf/config.xml' >"$dest"; then
  echo "opnsense: ssh ${USER}@${HOST} failed — skip"
  rm -f "$dest"
  exit 0
fi
hl_prune "$ROOT"
echo "opnsense: wrote ${dest}"
