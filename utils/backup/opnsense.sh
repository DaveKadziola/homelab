#!/usr/bin/env bash
# Copy OPNsense config.xml onto the NAS (F5). Runs on the NAS (run-nas.sh): it reaches the router on
# its IOT address without a firewall rule. The key OPNSENSE_BACKUP_SSH_PRIV is installed on the router
# with a forced command that can only print config.xml (utils/opnsense-backup-key.sh). Skips
# until that key exists or when the router is unreachable.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [[ "${HOMELAB_ENV}" != "prod" ]]; then
  echo "opnsense: only on prod — skip"
  exit 0
fi

HOST="${OPNSENSE_HOST:-192.168.20.1}"
key="$(mktemp)"
trap 'rm -f "$key" "${dest:-}.part"' EXIT
if ! hl_secret OPNSENSE_BACKUP_SSH_PRIV >"$key"; then
  echo "opnsense: OPNSENSE_BACKUP_SSH_PRIV missing — skip"
  exit 0
fi
printf '\n' >>"$key"
chmod 600 "$key"
if ! ping -c 1 -W 2 "$HOST" >/dev/null 2>&1; then
  echo "opnsense: ${HOST} unreachable — skip"
  exit 0
fi

# NAS-private root: config.xml holds password hashes and keys; no NFS client or share reaches it.
ROOT="$(hl_storage nas_private_root)/opnsense"
mkdir -p "$ROOT"
dest="${ROOT}/config-$(hl_stamp).xml"
# The forced command on the router ignores what is sent; the argument documents the intent.
ssh -i "$key" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
  "root@${HOST}" 'cat /conf/config.xml' >"${dest}.part"
if ! head -c 100 "${dest}.part" | grep -q '<?xml' || ! tail -c 200 "${dest}.part" | grep -q '</opnsense>'; then
  echo "opnsense: the router did not return a complete config.xml" >&2
  exit 1
fi
chmod 600 "${dest}.part"
mv "${dest}.part" "$dest"
hl_prune "$ROOT"
echo "opnsense: wrote ${dest}"
