#!/usr/bin/env bash
# Point the public Grocery HAProxy backend at 8101 (not Dozzle on 8080), check, keep or auto-revert.
#
# Usage:
#   ./utils/f2-opnsense-haproxy.sh --dry-run
#   ./utils/f2-opnsense-haproxy.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAN_HOST="${OPNSENSE_HOST:-192.168.1.1}"
KEY="${OPNSENSE_KEY:-$HOME/.ssh/daveadmin}"
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1
R=(ssh -o StrictHostKeyChecking=accept-new -i "$KEY" "root@${LAN_HOST}")

"${R[@]}" "env DRY_RUN=${DRY_RUN} REVERT_AFTER=${REVERT_AFTER} sh -s" < "${REPO_ROOT}/utils/f2-opnsense-haproxy-remote.sh"
[[ $DRY_RUN == 1 ]] && exit 0

sleep 3
fail=0
check() { if "${@:2}"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
check "live haproxy.conf backend 192.168.50.30:8101" bash -c "\"\${0}\" \"\${@:1}\" -o BatchMode=yes 'grep -q \"server grocery-app 192.168.50.30:8101\" /usr/local/etc/haproxy.conf'" "${R[@]}"
check "haproxy running, listening on WAN 443" bash -c "\"\${0}\" \"\${@:1}\" -o BatchMode=yes 'sockstat -4l | grep -q \"haproxy.*192.168.100.2:443\"'" "${R[@]}"
check "LAN -> internet (https)" curl -s -o /dev/null --max-time 8 https://github.com
check "root ssh over LAN" "${R[@]}" -o BatchMode=yes true

if [[ $fail == 0 ]]; then
  "${R[@]}" -o BatchMode=yes 'touch /tmp/homelab-haproxy-keep; pkill -F /tmp/homelab-haproxy-revert.pid' || true
  echo "all checks passed - change kept"
  out="${REPO_ROOT}/opnsense/backups/config-$(date +%Y%m%d-%H%M%S).xml"
  mkdir -p "$(dirname "$out")"
  "${R[@]}" -o BatchMode=yes 'cat /conf/config.xml' > "$out"
  chmod 600 "$out"; echo "local copy: $out"
else
  echo "a check failed - not confirmed; the router restores its backup within ${REVERT_AFTER}s"
  exit 1
fi
