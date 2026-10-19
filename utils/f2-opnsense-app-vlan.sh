#!/usr/bin/env bash
# Move APP from QinQ to a plain VLAN 51, check from Proxmox nic2, keep or let it auto-revert.
#
# Usage:
#   ./utils/f2-opnsense-app-vlan.sh --dry-run
#   ./utils/f2-opnsense-app-vlan.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAN_HOST="${OPNSENSE_HOST:-192.168.1.1}"
KEY="${OPNSENSE_KEY:-$HOME/.ssh/daveadmin}"
PVE=(ssh -o BatchMode=yes -i "${PVE_KEY:-$HOME/.ssh/homelab_dev_ed25519}" root@192.168.20.20)
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1
R=(ssh -o StrictHostKeyChecking=accept-new -i "$KEY" "root@${LAN_HOST}")

"${R[@]}" "env DRY_RUN=${DRY_RUN} REVERT_AFTER=${REVERT_AFTER} sh -s" < "${REPO_ROOT}/utils/f2-opnsense-app-vlan-remote.sh"
[[ $DRY_RUN == 1 ]] && exit 0

sleep 3
# Temporary vmbr1.51 with a test address on Proxmox; removed again. ARP, not ping: APP has no rule
# passing ICMP to the router.
app_probe() {
  "${PVE[@]}" 'bridge vlan add vid 51 dev vmbr1 self; ip link add link vmbr1 name vmbr1.51 type vlan id 51 && ip addr add 192.168.50.61/26 dev vmbr1.51 && ip link set vmbr1.51 up; sleep 3; ping -c1 -W1 192.168.50.50 >/dev/null 2>&1; ip neigh show 192.168.50.50 dev vmbr1.51 | grep -q lladdr; rc=$?; ip link del vmbr1.51; bridge vlan del vid 51 dev vmbr1 self; exit $rc' 2>/dev/null
}
fail=0
check() { if "${@:2}"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
check "Proxmox vmbr1 VLAN 51 -> APP gateway 192.168.50.50 (ARP)" app_probe
check "LAN -> internet (https)" curl -s -o /dev/null --max-time 8 https://github.com
check "IOT -> internet" ping -c2 -W2 -I wlan0 1.1.1.1
check "LAN -> Proxmox" ping -c2 -W2 192.168.20.20
check "root ssh over LAN" "${R[@]}" -o BatchMode=yes true

if [[ $fail == 0 ]]; then
  "${R[@]}" -o BatchMode=yes 'touch /tmp/homelab-app-keep; pkill -F /tmp/homelab-app-revert.pid'
  echo "all checks passed - change kept"
  out="${REPO_ROOT}/opnsense/backups/config-$(date +%Y%m%d-%H%M%S).xml"
  "${R[@]}" -o BatchMode=yes 'cat /conf/config.xml' > "$out"
  chmod 600 "$out"; echo "local copy: $out"
else
  echo "a check failed - not confirmed; the router restores its backup within ${REVERT_AFTER}s"
  exit 1
fi
