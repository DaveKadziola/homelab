#!/usr/bin/env bash
# Let APP reach the internet on the ports the apps use, check from a test client on VLAN 51 behind
# Proxmox and from ubuntu-apps, keep or auto-revert.
#
# Usage:
#   ./utils/opnsense-app-egress.sh --dry-run
#   ./utils/opnsense-app-egress.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAN_HOST="${OPNSENSE_HOST:-192.168.1.1}"
KEY="${OPNSENSE_KEY:-$HOME/.ssh/daveadmin}"
PVE=(ssh -o BatchMode=yes -i "${PVE_KEY:-$HOME/.ssh/homelab_prod_pve_ed25519}" root@192.168.20.20)
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1
R=(ssh -o StrictHostKeyChecking=accept-new -i "$KEY" "root@${LAN_HOST}")

"${R[@]}" "env DRY_RUN=${DRY_RUN} REVERT_AFTER=${REVERT_AFTER} sh -s" < "${REPO_ROOT}/utils/opnsense-app-egress-remote.sh"
[[ $DRY_RUN == 1 ]] && exit 0

# The test client has no resolver that answers on VLAN 51, so the targets are resolved here.
SMTP_IP="$(dig +short @"$LAN_HOST" smtp.protonmail.ch A | grep -m1 -E '^[0-9.]+$')"
ARCHIVE_IP="$(dig +short @"$LAN_HOST" archive.ubuntu.com A | grep -m1 -E '^[0-9.]+$')"
STUN_IP="$(dig +short @"$LAN_HOST" stun.cloudflare.com A | grep -m1 -E '^[0-9.]+$')"
sleep 3
# A test client in its own network namespace on Proxmox: vmbr1 VLAN 51, 192.168.50.61/26, gateway
# 192.168.50.50 - what ubuntu-apps will see. Prints one line per probe; removed again.
probe() {
  "${PVE[@]}" "SMTP_IP=${SMTP_IP} ARCHIVE_IP=${ARCHIVE_IP} STUN_IP=${STUN_IP} bash -s" <<'P' 2>/dev/null
bridge vlan add vid 51 dev vmbr1 self
ip netns add apptest
ip link add link vmbr1 name app51 type vlan id 51
ip link set app51 netns apptest
ip -n apptest addr add 192.168.50.61/26 dev app51
ip -n apptest link set app51 up; ip -n apptest link set lo up
ip -n apptest route add default via 192.168.50.50
sleep 3
ip netns exec apptest curl -s -o /dev/null -w "https %{http_code}\n" --max-time 8 --resolve github.com:443:140.82.121.4 https://github.com/ || echo "https fail"
# DNS via the APP gateway: AdGuard answers a query for another VLAN's router address (.20.1) from
# this VLAN's address (.50.50), so the resolver drops it - ubuntu-apps uses 192.168.50.50.
ip netns exec apptest python3 -c '
import random, socket, struct
q = struct.pack(">HHHHHH", random.randint(0, 65535), 0x0100, 1, 0, 0, 0) + b"\x06github\x03com\x00" + struct.pack(">HH", 1, 1)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(3); s.sendto(q, ("192.168.50.50", 53))
d, src = s.recvfrom(512); print("dns", src[0])' 2>/dev/null || echo "dns fail"
ip netns exec apptest timeout 3 bash -c "</dev/tcp/192.168.1.1/443" 2>/dev/null && echo "lan open" || echo "lan blocked"
ip netns exec apptest curl -s -o /dev/null -w "http %{http_code}\n" --max-time 8 --resolve "archive.ubuntu.com:80:${ARCHIVE_IP}" http://archive.ubuntu.com/ubuntu/ || echo "http fail"
ip netns exec apptest timeout 4 bash -c "</dev/tcp/${SMTP_IP}/587" 2>/dev/null && echo "smtp open" || echo "smtp closed"
ip netns exec apptest timeout 4 bash -c "</dev/tcp/140.82.121.4/22" 2>/dev/null && echo "ssh-out open" || echo "ssh-out closed"
ip netns exec apptest ping -c 1 -W 3 1.1.1.1 >/dev/null && echo "ping ok" || echo "ping fail"
# A STUN binding request, as Syncthing sends for NAT traversal.
ip netns exec apptest python3 -c '
import os, socket, struct
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(3)
s.sendto(struct.pack(">HHI", 1, 0, 0x2112A442) + os.urandom(12), (os.environ["STUN_IP"], 3478))
s.recvfrom(512); print("stun ok")' 2>/dev/null || echo "stun fail"
ip netns del apptest
bridge vlan del vid 51 dev vmbr1 self
P
}
out="$(probe)"; echo "$out" | sed 's/^/   probe: /'
fail=0
check() { if "${@:2}"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
check "APP -> internet (https)" grep -q "^https [23]" <<<"$out"
check "APP -> DNS" grep -q "^dns [0-9]" <<<"$out"
check "APP -/-> LAN" grep -q "^lan blocked" <<<"$out"
check "APP -> internet (http, apt)" grep -q "^http [23]" <<<"$out"
check "APP -> mail (587)" grep -q "^smtp open" <<<"$out"
check "APP -/-> internet SSH (22)" grep -q "^ssh-out closed" <<<"$out"
check "APP -> ping" grep -q "^ping ok" <<<"$out"
check "APP -> STUN (UDP 3478)" grep -q "^stun ok" <<<"$out"
check "LAN -> internet (https)" curl -s -o /dev/null --max-time 8 https://github.com
check "root ssh over LAN" "${R[@]}" -o BatchMode=yes true
APPS=(ssh -o BatchMode=yes -i "${PROD_KEY:-$HOME/.ssh/homelab_prod_ed25519}" ubuntu-prod@192.168.50.30)
check "ubuntu-apps: NFS from the NAS" "${APPS[@]}" 'timeout 10 ls /mnt/homelab/backups >/dev/null'
check "ubuntu-apps: apt update" "${APPS[@]}" 'sudo timeout 120 apt-get update -qq'

# No copy of config.xml on the laptop (audit S9): the router keeps the backup, the NAS a daily one.
if [[ $fail == 0 ]]; then
  "${R[@]}" -o BatchMode=yes 'touch /tmp/homelab-appfw-keep; pkill -F /tmp/homelab-appfw-revert.pid' || true
  echo "all checks passed - change kept"
else
  echo "a check failed - not confirmed; the router restores its backup within ${REVERT_AFTER}s"
  exit 1
fi
