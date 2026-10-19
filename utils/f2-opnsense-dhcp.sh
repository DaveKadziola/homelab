#!/usr/bin/env bash
# Fix the IOT DHCP static maps (.20.20 Proxmox, .20.13 Home Assistant), check, keep or auto-revert.
#
# Usage:
#   ./utils/f2-opnsense-dhcp.sh --dry-run
#   ./utils/f2-opnsense-dhcp.sh
#
# root logs in over LAN (192.168.1.1) with KEY. If a check fails, nothing is confirmed and the router
# restores its backup after REVERT_AFTER seconds by itself.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAN_HOST="${OPNSENSE_HOST:-192.168.1.1}"
KEY="${OPNSENSE_KEY:-$HOME/.ssh/daveadmin}"
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1
R=(ssh -o StrictHostKeyChecking=accept-new -i "$KEY" "root@${LAN_HOST}")

"${R[@]}" "env DRY_RUN=${DRY_RUN} REVERT_AFTER=${REVERT_AFTER} sh -s" < "${REPO_ROOT}/utils/f2-opnsense-dhcp-remote.sh"
[[ $DRY_RUN == 1 ]] && exit 0

sleep 3
fail=0
check() { if "${@:2}"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
check "dhcpd running" bash -c "\"\${0}\" \"\${@:1}\" -o BatchMode=yes 'pgrep -x dhcpd' >/dev/null" "${R[@]}"
check "LAN -> internet (https)" curl -s -o /dev/null --max-time 8 https://github.com
check "IOT -> internet" ping -c2 -W2 -I wlan0 1.1.1.1
check "root ssh over LAN" "${R[@]}" -o BatchMode=yes true

if [[ $fail == 0 ]]; then
  "${R[@]}" -o BatchMode=yes 'touch /tmp/homelab-dhcp-keep; pkill -F /tmp/homelab-dhcp-revert.pid'
  echo "all checks passed - change kept"
  out="${REPO_ROOT}/opnsense/backups/config-$(date +%Y%m%d-%H%M%S).xml"
  "${R[@]}" -o BatchMode=yes 'cat /conf/config.xml' > "$out"
  chmod 600 "$out"; echo "local copy: $out"
else
  echo "a check failed - not confirmed; the router restores its backup within ${REVERT_AFTER}s"
  exit 1
fi
