#!/usr/bin/env bash
# Close TCP 80 on the OPNsense WAN (it reached the AdGuard Home login), check pf, keep or auto-revert.
#
# Usage:
#   ./utils/opnsense-wan-http.sh --dry-run
#   ./utils/opnsense-wan-http.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAN_HOST="${OPNSENSE_HOST:-192.168.1.1}"
KEY="${OPNSENSE_KEY:-$HOME/.ssh/daveadmin}"
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1
R=(ssh -o StrictHostKeyChecking=accept-new -i "$KEY" "root@${LAN_HOST}")

"${R[@]}" "env DRY_RUN=${DRY_RUN} REVERT_AFTER=${REVERT_AFTER} sh -s" < "${REPO_ROOT}/utils/opnsense-wan-http-remote.sh"
[[ $DRY_RUN == 1 ]] && exit 0

sleep 3
rules="$(printf 'pfctl -sr | grep -E "^pass in .*on igc0"\n' | "${R[@]}" -o BatchMode=yes 'sh -s' 2>/dev/null)"
fail=0
check() { if "${@:2}"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
check "pf: no WAN pass rule for port 80" bash -c "! grep -qE 'port = (http|80) ' <<<\"\$0\"" "$rules"
check "pf: WAN 443 (HAProxy) still passes" grep -qE 'proto tcp .*port = (https|443) ' <<<"$rules"
check "pf: WAN UDP 51820 (WireGuard) still passes" grep -qE 'proto udp .*port = 51820 ' <<<"$rules"
check "grocery over HTTPS from LAN" bash -c '[ "$(curl -sk -o /dev/null -m 20 -w "%{http_code}" https://grocery.dkhomelabserver.xyz/)" = 200 ]'
check "LAN -> internet (https)" curl -s -o /dev/null --max-time 8 https://github.com
check "root ssh over LAN" "${R[@]}" -o BatchMode=yes true

if [[ $fail == 0 ]]; then
  "${R[@]}" -o BatchMode=yes 'touch /tmp/homelab-wanhttp-keep; pkill -F /tmp/homelab-wanhttp-revert.pid' || true
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
