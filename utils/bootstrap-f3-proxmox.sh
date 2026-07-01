#!/usr/bin/env bash
# Bootstrap F3 — set real Proxmox API URL in GitHub prod (no secrets generated here).
#
# Prerequisites: Proxmox online, API token created (docs/f3-proxmox.md F3-02).
#
# Usage:
#   PROXMOX_IP=192.168.20.20 ./utils/bootstrap-f3-proxmox.sh
#   ./utils/bootstrap-f3-proxmox.sh --set-token   # also prompt for token secret via gh

set -euo pipefail

REPO="${GITHUB_REPO:-DaveKadziola/homelab}"
PROXMOX_IP="${PROXMOX_IP:-192.168.20.20}"
API_URL="https://${PROXMOX_IP}:8006/api2/json"
SET_TOKEN=false

[[ "${1:-}" == "--set-token" ]] && SET_TOKEN=true

command -v gh >/dev/null || { echo "gh required"; exit 1; }

echo "Proxmox API URL: $API_URL"
gh variable set PROXMOX_API_URL --env prod --repo "$REPO" --body "$API_URL"
echo "set variable PROXMOX_API_URL (prod)"

if $SET_TOKEN; then
  echo "Paste API token secret (input hidden):"
  read -rs TOKEN
  printf '%s' "$TOKEN" | gh secret set PROXMOX_API_TOKEN_SECRET --env prod --repo "$REPO" --body -
  unset TOKEN
  echo "set secret PROXMOX_API_TOKEN_SECRET (prod)"
fi

echo ""
echo "Next:"
echo "  1. Store token in Bitwarden homelab/PROXMOX_API_TOKEN_SECRET/prod"
echo "  2. ./utils/f3-verify.sh"
echo "  3. terraform plan/apply — docs/f3-proxmox.md"
