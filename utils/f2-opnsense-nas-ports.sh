#!/usr/bin/env bash
# Limit APP -> NAS to NFS 2049/111 (+ SSH 22 from ubuntu-apps), check pf, keep or auto-revert.
#
# Usage:
#   ./utils/f2-opnsense-nas-ports.sh --dry-run
#   ./utils/f2-opnsense-nas-ports.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAN_HOST="${OPNSENSE_HOST:-192.168.1.1}"
KEY="${OPNSENSE_KEY:-$HOME/.ssh/daveadmin}"
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1
R=(ssh -o StrictHostKeyChecking=accept-new -i "$KEY" "root@${LAN_HOST}")

"${R[@]}" "env DRY_RUN=${DRY_RUN} REVERT_AFTER=${REVERT_AFTER} sh -s" < "${REPO_ROOT}/utils/f2-opnsense-nas-ports-remote.sh"
[[ $DRY_RUN == 1 ]] && exit 0

sleep 3
rules="$(printf 'pfctl -sr | grep 192.168.20.12\n' | "${R[@]}" -o BatchMode=yes 'sh -s' 2>/dev/null)"
fail=0
check() { if "${@:2}"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
check "pf: APP -> NAS port 2049 (nfsd)" grep -qE 'to 192\.168\.20\.12 port = (nfsd|2049)' <<<"$rules"
check "pf: APP -> NAS port 111 (sunrpc)" grep -qE 'to 192\.168\.20\.12 port = (sunrpc|111)' <<<"$rules"
check "pf: 192.168.50.30 -> NAS port 22" grep -qE 'from 192\.168\.50\.30 to 192\.168\.20\.12 port = (ssh|22)' <<<"$rules"
check "pf: no APP -> NAS rule without a port" bash -c "! grep -E 'to 192\.168\.20\.12 flags' <<<\"\$0\"" "$rules"
check "LAN -> internet (https)" curl -s -o /dev/null --max-time 8 https://github.com
check "root ssh over LAN" "${R[@]}" -o BatchMode=yes true

if [[ $fail == 0 ]]; then
  "${R[@]}" -o BatchMode=yes 'touch /tmp/homelab-nasports-keep; pkill -F /tmp/homelab-nasports-revert.pid' || true
  echo "all checks passed - change kept"
  out="${REPO_ROOT}/opnsense/backups/config-$(date +%Y%m%d-%H%M%S).xml"
  mkdir -p "$(dirname "$out")"
  "${R[@]}" -o BatchMode=yes 'cat /conf/config.xml' > "$out"
  chmod 600 "$out"; echo "local copy: $out"
else
  echo "$rules"
  echo "a check failed - not confirmed; the router restores its backup within ${REVERT_AFTER}s"
  exit 1
fi
