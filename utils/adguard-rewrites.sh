#!/usr/bin/env bash
# Add the AdGuard Home rewrites that make the app names resolve at home (decision 0007), check, keep
# or auto-revert. One rewrite per name of utils/gen-proxy-config.py --file adguard (prod names ->
# ubuntu-apps, DEV names -> ubuntu-apps-dev, which only the laptop reaches). Not part of any deploy:
# a live router change, run by the owner's decision (AGENTS.md section 11).
#
# Usage:
#   ./utils/adguard-rewrites.sh --dry-run
#   ./utils/adguard-rewrites.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAN_HOST="${OPNSENSE_HOST:-192.168.1.1}"
KEY="${OPNSENSE_KEY:-$HOME/.ssh/daveadmin}"
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1
R=(ssh -o StrictHostKeyChecking=accept-new -i "$KEY" "root@${LAN_HOST}")

rewrites="$(for env in prod dev; do python3 "${REPO_ROOT}/utils/gen-proxy-config.py" --env "$env" --file adguard; done)"
# The router's root shell is csh: the multi-line list goes in front of the script, not on its command line.
{ printf "REWRITES='%s'\nexport REWRITES\n" "$rewrites"; cat "${REPO_ROOT}/utils/adguard-rewrites-remote.sh"; } |
  "${R[@]}" "env DRY_RUN=${DRY_RUN} REVERT_AFTER=${REVERT_AFTER} sh -s"
[[ $DRY_RUN == 1 ]] && exit 0

sleep 5
fail=0
check() { if "${@:2}"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
while read -r name ip; do
  check "$name -> $ip" bash -c '[[ "$(dig +short "$1" @"$3" | tail -1)" == "$2" ]]' _ "$name" "$ip" "$LAN_HOST"
done <<<"$rewrites"
check "proxmox.dkhomelabserver.xyz unchanged" bash -c '[[ "$(dig +short proxmox.dkhomelabserver.xyz @"$1")" == 192.168.20.20 ]]' _ "$LAN_HOST"
check "github.com still resolves" bash -c '[[ -n "$(dig +short github.com @"$1")" ]]' _ "$LAN_HOST"

if [[ $fail == 0 ]]; then
  "${R[@]}" -o BatchMode=yes 'touch /tmp/homelab-rewrites-keep; pkill -F /tmp/homelab-rewrites-revert.pid' || true
  echo "all checks passed - change kept"
else
  echo "a check failed - not confirmed; the router restores its backup within ${REVERT_AFTER}s"
  exit 1
fi
