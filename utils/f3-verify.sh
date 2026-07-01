#!/usr/bin/env bash
# F3 verification — Proxmox + GH prod placeholders (no secrets printed).
#
# Usage: ./utils/f3-verify.sh

set -euo pipefail

PROXMOX_IP="${PROXMOX_IP:-192.168.20.20}"
PROXMOX_API_URL="${PROXMOX_API_URL:-https://${PROXMOX_IP}:8006/api2/json}"
REPO="${GITHUB_REPO:-DaveKadziola/homelab}"

pass=0
fail=0
warn=0

ok() { echo "OK   $*"; ((pass++)) || true; }
bad() { echo "FAIL $*"; ((fail++)) || true; }
warn_msg() { echo "WARN $*"; ((warn++)) || true; }

echo "=== F3 verify ($(date -Iseconds)) ==="
echo ""

echo "--- F3-01 Proxmox host ---"
if ping -c1 -W2 "$PROXMOX_IP" &>/dev/null; then
  ok "ping Proxmox ($PROXMOX_IP)"
else
  warn_msg "ping Proxmox ($PROXMOX_IP) — host offline or ICMP blocked"
fi

if curl -fsSk --max-time 5 "${PROXMOX_API_URL%/api2/json}/" &>/dev/null; then
  ok "HTTPS Proxmox UI ($PROXMOX_IP:8006)"
else
  warn_msg "HTTPS :8006 — API/UI not reachable (expected before bootstrap)"
fi
echo ""

echo "--- F3-03 GitHub prod variables ---"
if command -v gh &>/dev/null; then
  url=$(gh variable get PROXMOX_API_URL --env prod --repo "$REPO" 2>/dev/null || true)
  if [[ -n "$url" && "$url" != *example* && "$url" == *":8006"* ]]; then
    ok "PROXMOX_API_URL prod set"
  else
    warn_msg "PROXMOX_API_URL prod still placeholder — run bootstrap-f3-proxmox.sh"
  fi
else
  warn_msg "gh CLI not installed"
fi
echo ""

echo "--- F2 prep (still required) ---"
if [[ -x "$(dirname "$0")/f2-verify.sh" ]]; then
  "$(dirname "$0")/f2-verify.sh" || true
fi
echo ""

echo "--- Summary ---"
echo "pass=$pass fail=$fail warn=$warn"
echo "See: docs/f3-proxmox.md"

[[ "$fail" -eq 0 ]]
