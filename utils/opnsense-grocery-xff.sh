#!/usr/bin/env bash
# Send X-Forwarded-For and X-Forwarded-Proto from the public Grocery HAProxy backend, check, keep
# or auto-revert. Only backend "grocery" changes.
#
# Usage:
#   ./utils/opnsense-grocery-xff.sh --dry-run
#   ./utils/opnsense-grocery-xff.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAN_HOST="${OPNSENSE_HOST:-192.168.1.1}"
KEY="${OPNSENSE_KEY:-$HOME/.ssh/daveadmin}"
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1
R=(ssh -o StrictHostKeyChecking=accept-new -i "$KEY" "root@${LAN_HOST}")

"${R[@]}" "env DRY_RUN=${DRY_RUN} REVERT_AFTER=${REVERT_AFTER} sh -s" < "${REPO_ROOT}/utils/opnsense-grocery-xff-remote.sh"
[[ $DRY_RUN == 1 ]] && exit 0

sleep 3
fail=0
check() { if "${@:2}"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
block="$("${R[@]}" -o BatchMode=yes "sed -n '/^backend grocery/,/^\$/p' /usr/local/etc/haproxy.conf" || true)"
check "live backend grocery: option forwardfor" grep -q "option forwardfor" <<<"$block"
check "live backend grocery: X-Forwarded-Proto https" grep -q "set-header X-Forwarded-Proto https" <<<"$block"
check "https://grocery.dkhomelabserver.xyz answers 200" bash -c '[[ "$(curl -sS -o /dev/null -m 10 -w "%{http_code}" https://grocery.dkhomelabserver.xyz/)" == 200 ]]'
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
