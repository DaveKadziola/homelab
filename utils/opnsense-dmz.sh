#!/usr/bin/env bash
# Move DMZ out of the APP /26 on OPNsense, check, keep or let it auto-revert.
#
# Usage:
#   ./utils/opnsense-dmz.sh --dry-run
#   ./utils/opnsense-dmz.sh
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

"${R[@]}" "env DRY_RUN=${DRY_RUN} REVERT_AFTER=${REVERT_AFTER} sh -s" < "${REPO_ROOT}/utils/opnsense-dmz-remote.sh"
[[ $DRY_RUN == 1 ]] && exit 0

sleep 5
fail=0
check() { if "${@:2}"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
reach() { ping -c2 -W2 "$1" >/dev/null 2>&1; }
check "LAN -> internet (https)" curl -s -o /dev/null --max-time 8 https://github.com
check "LAN -> DNS on 192.168.1.1" bash -c '[[ -n $(dig +short +time=3 +tries=1 @192.168.1.1 github.com A) ]]'
check "LAN -> new DMZ gateway 192.168.50.65" reach 192.168.50.65
check "LAN -> APP gateway 192.168.50.50" reach 192.168.50.50
check "old DMZ address 192.168.50.1 gone" bash -c '! ping -c2 -W2 192.168.50.1 >/dev/null 2>&1'
check "IOT -> internet" ping -c2 -W2 -I wlan0 1.1.1.1
check "root ssh over LAN" "${R[@]}" -o BatchMode=yes true

if [[ $fail == 0 ]]; then
  "${R[@]}" -o BatchMode=yes 'touch /tmp/homelab-dmz-keep; pkill -F /tmp/homelab-dmz-revert.pid'
  echo "all checks passed - change kept"
  out="${REPO_ROOT}/opnsense/backups/config-$(date +%Y%m%d-%H%M%S).xml"
  "${R[@]}" -o BatchMode=yes 'cat /conf/config.xml' > "$out"
  chmod 600 "$out"; echo "local copy: $out"
else
  echo "a check failed - not confirmed; the router restores its backup within ${REVERT_AFTER}s"
  exit 1
fi
