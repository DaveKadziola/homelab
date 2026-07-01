#!/usr/bin/env bash
# F2 verification — checks reachable from laptop (does not log into OPNsense).
#
# Usage: ./utils/f2-verify.sh
#
# Exit 0 if blocking gates (F2-01 ping) pass; exit 1 otherwise.

set -euo pipefail

IOT_GW="${IOT_GW:-192.168.20.1}"
APP_GW="${APP_GW:-192.168.50.50}"
PROXMOX_IP="${PROXMOX_IP:-192.168.20.20}"
GROCERY_HOST="${GROCERY_HOST:-grocery.dkhomelabserver.xyz}"
DNS_SERVER="${DNS_SERVER:-8.8.8.8}"

pass=0
fail=0
warn=0

check_ping() {
  local name="$1" host="$2"
  if ping -c1 -W2 "$host" &>/dev/null; then
    echo "OK   ping $name ($host)"
    ((pass++)) || true
    return 0
  fi
  echo "FAIL ping $name ($host)"
  ((fail++)) || true
  return 1
}

check_dns() {
  local host="$1"
  if command -v dig &>/dev/null; then
    if ip=$(dig @"$DNS_SERVER" +short "$host" 2>/dev/null | grep -E '^[0-9.]+$' | head -1); then
      echo "OK   DNS $host → $ip (via $DNS_SERVER)"
      ((pass++)) || true
      return 0
    fi
  fi
  if command -v getent &>/dev/null && ip=$(getent ahosts "$host" 2>/dev/null | awk '{print $1; exit}'); then
    echo "OK   DNS $host → $ip (getent)"
    ((pass++)) || true
    return 0
  fi
  echo "WARN DNS $host — could not resolve (F2-05; check A record)"
  ((warn++)) || true
  return 1
}

check_https() {
  local url="$1"
  if curl -fsSI --max-time 5 "$url" &>/dev/null; then
    echo "OK   HTTPS $url responds"
    ((pass++)) || true
    return 0
  fi
  echo "WARN HTTPS $url — no response (expected until F2-05/F4)"
  ((warn++)) || true
  return 1
}

check_ssh_opnsense() {
  local host="$1"
  if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no "root@${host}" exit 2>/dev/null; then
    echo "OK   SSH root@${host} (key auth)"
    ((pass++)) || true
    return 0
  fi
  echo "WARN SSH root@${host} — no key auth (use OPNsense UI or password for backup)"
  ((warn++)) || true
  return 1
}

echo "=== F2 verify ($(date -Iseconds)) ==="
echo ""

echo "--- F2-01 VLAN gateways ---"
check_ping "IOT gateway" "$IOT_GW" || true
check_ping "APP gateway" "$APP_GW" || true
echo ""

echo "--- F3 prep (optional) ---"
if ping -c1 -W2 "$PROXMOX_IP" &>/dev/null; then
  echo "OK   ping Proxmox ($PROXMOX_IP)"
  ((pass++)) || true
else
  echo "WARN Proxmox ($PROXMOX_IP) — not online yet (expected before F3)"
  ((warn++)) || true
fi
echo ""

echo "--- F2-05 Grocery public ---"
check_dns "$GROCERY_HOST" || true
check_https "https://${GROCERY_HOST}/" || true
echo ""

echo "--- F2-06 backup path ---"
check_ssh_opnsense "${OPNSENSE_HOST:-192.168.1.1}" || true
if [[ -x "$(dirname "$0")/backup-opnsense-config.sh" ]]; then
  echo "INFO backup script: utils/backup-opnsense-config.sh"
fi
echo ""

echo "--- Summary ---"
echo "pass=$pass fail=$fail warn=$warn"
echo ""
echo "Manual steps: docs/opnsense-baseline.md + docs/opnsense-ui-walkthrough.md"
echo "After OPNsense work: OPNSENSE_HOST=192.168.1.1 ./utils/f2-opnsense-apply.sh"

if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
exit 0
