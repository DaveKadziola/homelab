#!/usr/bin/env bash
# Let the NAS fetch OPNsense config.xml: add its key to root with a forced command
# (command="cat /conf/config.xml",restrict), check, keep or auto-revert. Not part of any deploy;
# run by the owner's decision (AGENTS.md section 11: live router change).
#
# Usage:
#   ./utils/opnsense-backup-key.sh --dry-run
#   ./utils/opnsense-backup-key.sh
#
# Key: OPNSENSE_BACKUP_SSH_PRIV in ~/.homelab-secrets/prod/ (made with ssh-keygen if missing; then
# push it to the GitHub environment prod with utils/sync-secrets-to-github.py, so the deploy writes it
# to the NAS). Checks after the change: the new key returns config.xml and nothing else, the admin key
# still opens a shell.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAN_HOST="${OPNSENSE_HOST:-192.168.1.1}"
KEY="${OPNSENSE_KEY:-$HOME/.ssh/daveadmin}"
BACKUP_KEY="${HOMELAB_SECRETS_DIR:-$HOME/.homelab-secrets}/prod/OPNSENSE_BACKUP_SSH_PRIV"
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1
R=(ssh -o StrictHostKeyChecking=accept-new -i "$KEY" "root@${LAN_HOST}")

if [[ ! -f "$BACKUP_KEY" ]]; then
  if [[ $DRY_RUN == 1 ]]; then echo "would: ssh-keygen $BACKUP_KEY"; else
    (umask 077; ssh-keygen -q -t ed25519 -N "" -C homelab-opnsense-backup-prod -f "$BACKUP_KEY")
    rm -f "${BACKUP_KEY}.pub"
  fi
fi
pub="$( [[ -f "$BACKUP_KEY" ]] && ssh-keygen -y -f "$BACKUP_KEY" || echo "ssh-ed25519 AAAA-dry-run homelab-opnsense-backup-prod")"

"${R[@]}" "env DRY_RUN=${DRY_RUN} REVERT_AFTER=${REVERT_AFTER} PUBKEY='${pub}' sh -s" < "${REPO_ROOT}/utils/opnsense-backup-key-remote.sh"
[[ $DRY_RUN == 1 ]] && exit 0

sleep 3
fail=0
check() { if "${@:2}"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
B=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$BACKUP_KEY" "root@${LAN_HOST}")
check "backup key returns config.xml" bash -c '"$@" "uname" | head -c 100 | grep -q "<?xml"' _ "${B[@]}"
# The whole config.xml contains the word FreeBSD. Only a shell's first line is exactly that.
check "backup key cannot run a command" bash -c '! "$@" "uname" | head -n 1 | grep -q "^FreeBSD"' _ "${B[@]}"
check "admin key still opens a shell" "${R[@]}" -o BatchMode=yes true

if [[ $fail == 0 ]]; then
  "${R[@]}" -o BatchMode=yes 'touch /tmp/homelab-backupkey-keep; pkill -F /tmp/homelab-backupkey-revert.pid' || true
  echo "all checks passed - change kept"
else
  echo "a check failed - not confirmed; the router restores its backup within ${REVERT_AFTER}s"
  exit 1
fi
