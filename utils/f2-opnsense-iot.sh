#!/usr/bin/env bash
# Close the IOT allow-all on OPNsense, check from the IOT VLAN, keep or let it auto-revert.
#
# Usage (from a laptop with a NIC on IOT, here wlan0 192.168.20.101):
#   ./utils/f2-opnsense-iot.sh --dry-run
#   ./utils/f2-opnsense-iot.sh
#
# root logs in over LAN (192.168.1.1), which this change does not touch, with KEY (root's
# authorized keys in System > Access > Users) or a password prompt. The check and the keep
# flag use daveadmin over IOT. If a check fails, nothing is confirmed and the router restores its
# backup after REVERT_AFTER seconds by itself.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAN_HOST="${OPNSENSE_HOST:-192.168.1.1}"
IOT_IF="${IOT_IF:-wlan0}"
IOT_SRC="${IOT_SRC:-192.168.20.101}"
KEY="${OPNSENSE_KEY:-$HOME/.ssh/daveadmin}"
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

ssh -o StrictHostKeyChecking=accept-new -i "$KEY" "root@${LAN_HOST}" \
  "env DRY_RUN=${DRY_RUN} REVERT_AFTER=${REVERT_AFTER} sh -s" < "${REPO_ROOT}/utils/f2-opnsense-iot-remote.sh"
[[ $DRY_RUN == 1 ]] && exit 0

sleep 5
reach() { ping -c2 -W2 -I "$IOT_IF" "$1" >/dev/null 2>&1; }
fail=0
check() { if "${@:2}"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
check "IOT -> internet (https)" curl -s -o /dev/null --interface "$IOT_IF" --max-time 8 https://github.com
check "IOT -> DNS on 192.168.20.1" bash -c "[[ -n \$(dig +short +time=3 +tries=1 -b $IOT_SRC @192.168.20.1 github.com A) ]]"
check "IOT -> router 192.168.20.1" reach 192.168.20.1
check "IOT -> LAN 192.168.1.1" reach 192.168.1.1
check "IOT -/-> HOME OFFICE 192.168.10.1" bash -c "! ping -c2 -W2 -I $IOT_IF 192.168.10.1 >/dev/null 2>&1"
check "IOT -/-> GUEST 192.168.30.1" bash -c "! ping -c2 -W2 -I $IOT_IF 192.168.30.1 >/dev/null 2>&1"

if [[ $fail == 0 ]]; then
  ssh -o BatchMode=yes -b "$IOT_SRC" -i "$KEY" daveadmin@192.168.20.1 'touch /tmp/homelab-iot-keep'
  echo "all checks passed - change kept"
  out="${REPO_ROOT}/opnsense/backups/config-$(date +%Y%m%d-%H%M%S).xml"
  ssh -o BatchMode=yes -b "$IOT_SRC" -i "$KEY" daveadmin@192.168.20.1 'cat /conf/config.xml' > "$out"
  chmod 600 "$out"; echo "local copy: $out"
else
  echo "a check failed - not confirmed; the router restores its backup within ${REVERT_AFTER}s"
  exit 1
fi
