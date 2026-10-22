#!/usr/bin/env bash
# Make the OPNsense DNS redirect work for UDP, check from LAN and IOT, keep or let it auto-revert.
#
# Usage:
#   ./utils/opnsense-dns.sh --dry-run
#   ./utils/opnsense-dns.sh
#
# root logs in over LAN (192.168.1.1) with KEY. If a check fails, nothing is confirmed and the router
# restores its backup after REVERT_AFTER seconds by itself.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAN_HOST="${OPNSENSE_HOST:-192.168.1.1}"
KEY="${OPNSENSE_KEY:-$HOME/.ssh/daveadmin}"
IOT_IF="${IOT_IF:-wlan0}"
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1
R=(ssh -o StrictHostKeyChecking=accept-new -i "$KEY" "root@${LAN_HOST}")

"${R[@]}" "env DRY_RUN=${DRY_RUN} REVERT_AFTER=${REVERT_AFTER} sh -s" < "${REPO_ROOT}/utils/opnsense-dns-remote.sh"
[[ $DRY_RUN == 1 ]] && exit 0

sleep 5
# UDP DNS query bound to one interface; dig cannot bind a device.
udp_dns() {
  python3 -I - "$1" "$2" <<'PY'
import random, socket, struct, sys
dev, dst = sys.argv[1], sys.argv[2]
q = struct.pack(">HHHHHH", random.randint(0, 65535), 0x0100, 1, 0, 0, 0)
q += b"".join(bytes([len(p)]) + p.encode() for p in "github.com".split(".")) + b"\0" + struct.pack(">HH", 1, 1)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(3)
s.setsockopt(socket.SOL_SOCKET, 25, dev.encode() + b"\0")  # SO_BINDTODEVICE
s.sendto(q, (dst, 53))
data, src = s.recvfrom(512)
sys.exit(0 if src[0] == dst and data[:2] == q[:2] else 1)
PY
}
fail=0
check() { if "${@:2}"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
check "LAN UDP -> 8.8.8.8 (redirected)" udp_dns eth0 8.8.8.8
check "LAN TCP -> 8.8.8.8 (redirected)" bash -c '[[ -n $(dig +tcp +short +time=3 +tries=1 @8.8.8.8 github.com A) ]]'
check "LAN UDP -> 192.168.1.1" udp_dns eth0 192.168.1.1
check "IOT UDP -> 8.8.8.8 (redirected)" udp_dns "$IOT_IF" 8.8.8.8
check "IOT UDP -> 192.168.20.1" udp_dns "$IOT_IF" 192.168.20.1
check "LAN -> internet (https)" curl -s -o /dev/null --max-time 8 https://github.com
check "root ssh over LAN" "${R[@]}" -o BatchMode=yes true

if [[ $fail == 0 ]]; then
  "${R[@]}" -o BatchMode=yes 'touch /tmp/homelab-dns-keep; pkill -F /tmp/homelab-dns-revert.pid'
  echo "all checks passed - change kept"
  out="${REPO_ROOT}/opnsense/backups/config-$(date +%Y%m%d-%H%M%S).xml"
  "${R[@]}" -o BatchMode=yes 'cat /conf/config.xml' > "$out"
  chmod 600 "$out"; echo "local copy: $out"
else
  echo "a check failed - not confirmed; the router restores its backup within ${REVERT_AFTER}s"
  exit 1
fi
