#!/usr/bin/env bash
# Phase 2 router lockdown, one step at a time: change OPNsense, probe from the networks it touches,
# keep the change only when every probe passes; otherwise the router restores its backup within
# REVERT_AFTER seconds (utils/opnsense-lockdown-remote.sh has the rules).
#
# Usage:
#   ./utils/opnsense-lockdown.sh admins|iot|ssh --dry-run
#   ./utils/opnsense-lockdown.sh admins|iot|ssh --selftest   # edit a copy twice on the router
#   ./utils/opnsense-lockdown.sh admins|iot|ssh

set -euo pipefail

STEP="${1:?usage: $0 admins|iot|ssh [--dry-run|--selftest]}"
MODE="${2:-}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAN_HOST="${OPNSENSE_HOST:-192.168.1.1}"
KEY="${OPNSENSE_KEY:-$HOME/.ssh/daveadmin}"
PVE=(ssh -o BatchMode=yes -i "${PVE_KEY:-$HOME/.ssh/homelab_prod_pve_ed25519}" root@192.168.20.20)
NAS=(ssh -o BatchMode=yes -i "${PROD_KEY:-$HOME/.ssh/homelab_prod_ed25519}" ubuntu-prod@192.168.20.12)
REVERT_AFTER="${REVERT_AFTER:-300}"
R=(ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -i "$KEY" "root@${LAN_HOST}")
env=(STEP="$STEP" REVERT_AFTER="$REVERT_AFTER")
case "$MODE" in
  --dry-run) env+=(DRY_RUN=1) ;;
  --selftest) env+=(SELFTEST=1) ;;
  "") ;;
  *) echo "unknown option: $MODE" >&2; exit 2 ;;
esac

"${R[@]}" "env ${env[*]} sh -s" < "${REPO_ROOT}/utils/opnsense-lockdown-remote.sh"
[[ -z "$MODE" ]] || exit 0

sleep 5
fail=0
check() { if "${@:2}"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
open() { timeout 4 bash -c "</dev/tcp/$1/$2" 2>/dev/null; }
closed() { ! open "$@"; }
# Run on a remote host: "<command> tcp host port" prints open/closed.
remote_tcp='t() { timeout 4 bash -c "</dev/tcp/$1/$2" 2>/dev/null && echo "$1:$2 open" || echo "$1:$2 closed"; }'

case "$STEP" in
  admins)
    lan_ip="$(ip -4 -br addr show | awk '$3 ~ /^192\.168\.1\./ {split($3, a, "/"); print a[1]; exit}')"
    echo "   this laptop on LAN: ${lan_ip:-none}"
    if [[ "$lan_ip" == 192.168.1.20 ]]; then admin=open; else admin=closed; fi
    check "router SSH from LAN (anti-lockout)" "${R[@]}" true
    check "router GUI 443 from LAN" open "$LAN_HOST" 443
    check "DNS through the router" bash -c "dig +short +time=3 @${LAN_HOST} github.com | grep -q ."
    check "Samba 445 on the NAS" open 192.168.20.12 445
    check "apps by name (Caddy 443)" open 192.168.50.30 443
    check "unbound 53530 closed" closed "$LAN_HOST" 53530
    check "Proxmox 8006 ${admin} for ${lan_ip:-this host}" "$admin" 192.168.20.20 8006
    check "Postgres 5432 ${admin} for ${lan_ip:-this host}" "$admin" 192.168.50.30 5432
    check "AdGuard UI 8443 ${admin} for ${lan_ip:-this host}" "$admin" "$LAN_HOST" 8443
    check "DHCP server running" "${R[@]}" 'pgrep -q dhcpd'
    ;;
  iot)
    # A test client in its own network namespace on Proxmox, on VLAN 20 like any IOT device.
    out="$("${PVE[@]}" 'bash -s' <<'P' 2>/dev/null
t() { ip netns exec iottest timeout 4 bash -c "</dev/tcp/$1/$2" 2>/dev/null && echo "client $1:$2 open" || echo "client $1:$2 closed"; }
ip netns add iottest
ip link add iot99 link vmbr0.20 type macvlan mode bridge
ip link set iot99 netns iottest
ip -n iottest addr add 192.168.20.99/24 dev iot99
ip -n iottest link set iot99 up; ip -n iottest link set lo up
ip -n iottest route add default via 192.168.20.1
sleep 3
ip netns exec iottest ping -c 1 -W 2 192.168.20.1 >/dev/null && echo "client ping router ok" || echo "client ping router fail"
ip netns exec iottest python3 -c '
import random, socket, struct
q = struct.pack(">HHHHHH", random.randint(0, 65535), 0x0100, 1, 0, 0, 0) + b"\x06github\x03com\x00" + struct.pack(">HH", 1, 1)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(3); s.sendto(q, ("192.168.20.1", 53))
s.recvfrom(512); print("client dns ok")' 2>/dev/null || echo "client dns fail"
ip netns exec iottest curl -s -o /dev/null -w "client https %{http_code}\n" --max-time 8 https://github.com/ || echo "client https fail"
t 192.168.20.1 22; t 192.168.20.1 443; t 192.168.1.1 443; t 192.168.50.30 8090; t 192.168.50.30 443
ip netns del iottest
P
)"
    echo "$out" | sed 's/^/   probe: /'
    check "IOT client: ping the router" grep -q "^client ping router ok" <<<"$out"
    check "IOT client: DNS" grep -q "^client dns ok" <<<"$out"
    check "IOT client: internet (https)" grep -q "^client https [23]" <<<"$out"
    for t in "192.168.20.1:22" "192.168.20.1:443" "192.168.1.1:443" "192.168.50.30:8090" "192.168.50.30:443"; do
      check "IOT client: ${t} closed" grep -q "^client ${t} closed" <<<"$out"
    done
    nas="$("${NAS[@]}" "bash -c '$remote_tcp; ping -c 1 -W 2 192.168.20.1 >/dev/null && echo ping ok; t 192.168.20.1 22; t 192.168.50.30 8090; t 192.168.50.30 2283; t 192.168.50.30 5432'" 2>/dev/null)"
    echo "$nas" | sed 's/^/   nas: /'
    check "NAS: ping the router (backup precheck)" grep -q "^ping ok" <<<"$nas"
    check "NAS: router SSH (backup)" grep -q "192.168.20.1:22 open" <<<"$nas"
    check "NAS: Beszel hub 8090" grep -q "192.168.50.30:8090 open" <<<"$nas"
    check "NAS: Immich 2283" grep -q "192.168.50.30:2283 open" <<<"$nas"
    check "NAS: Postgres 5432 closed" grep -q "192.168.50.30:5432 closed" <<<"$nas"
    pve="$("${PVE[@]}" "bash -c '$remote_tcp; t 192.168.50.30 8090; t 192.168.50.30 22; t 192.168.50.30 5432; t 192.168.20.1 22; pct exec 110 -- bash -c \"</dev/tcp/192.168.50.30/5432\" 2>/dev/null && echo runner 5432 open || echo runner 5432 closed'" 2>/dev/null)"
    echo "$pve" | sed 's/^/   pve: /'
    check "Proxmox: Beszel hub 8090" grep -q "192.168.50.30:8090 open" <<<"$pve"
    check "Proxmox: NIC mail SSH to apps" grep -q "192.168.50.30:22 open" <<<"$pve"
    check "Proxmox: Postgres 5432 closed" grep -q "192.168.50.30:5432 closed" <<<"$pve"
    check "Proxmox: router SSH closed" grep -q "192.168.20.1:22 closed" <<<"$pve"
    check "prod runner: apps reachable for the tests" grep -q "runner 5432 open" <<<"$pve"
    ;;
  ssh)
    check "root SSH by key" "${R[@]}" true
    deny="$(ssh -o BatchMode=yes -o PubkeyAuthentication=no -o PreferredAuthentications=keyboard-interactive,password \
      -o StrictHostKeyChecking=accept-new "root@${LAN_HOST}" true 2>&1 || true)"
    echo "   no key: ${deny##*$'\n'}"
    check "no password or keyboard-interactive offered" bash -c '[[ "$1" == *"(publickey)"* ]]' _ "$deny"
    check "sshd -T: password and kbd-interactive off" "${R[@]}" \
      'sshd -T | grep -q "^passwordauthentication no" && sshd -T | grep -q "^kbdinteractiveauthentication no"'
    ;;
  *) echo "unknown step: $STEP" >&2; exit 2 ;;
esac

if [[ $fail == 0 ]]; then
  "${R[@]}" "touch /tmp/homelab-lockdown-${STEP}-keep; pkill -F /tmp/homelab-lockdown-${STEP}-revert.pid" || true
  echo "all checks passed - change kept"
else
  echo "a check failed - not confirmed; the router restores its backup within ${REVERT_AFTER}s"
  exit 1
fi
