#!/usr/bin/env bash
# Point GitHub dev env at nested Proxmox API (libvirt VM "Proxmox").
#
# Usage:
#   ./utils/ensure-dev-proxmox.sh
#   ./utils/bootstrap-dev-proxmox.sh
#   ./utils/bootstrap-dev-proxmox.sh --set-token

set -euo pipefail

REPO="${GITHUB_REPO:-DaveKadziola/homelab}"
SET_TOKEN=false
[[ "${1:-}" == "--set-token" ]] && SET_TOKEN=true

"$(dirname "$0")/ensure-dev-proxmox.sh"

IP=$(virsh -c "${LIBVIRT_URI:-qemu:///system}" domifaddr "${DEV_PROXMOX_VM_NAME:-Proxmox}" 2>/dev/null \
  | awk '/ipv4/ {print $4}' | cut -d/ -f1 | head -1)

if [[ -z "$IP" ]]; then
  echo "ERROR: could not detect nested Proxmox IP"
  exit 1
fi

API_URL="https://${IP}:8006/api2/json"
NODE="${PROXMOX_NODE_NAME:-pve}"

command -v gh >/dev/null || { echo "gh required"; exit 1; }

echo "Nested Proxmox: ${API_URL} (node: ${NODE})"
gh variable set PROXMOX_API_URL --env dev --repo "$REPO" --body "$API_URL"
gh variable set PROXMOX_NODE_NAME --env dev --repo "$REPO" --body "$NODE"
echo "set PROXMOX_API_URL + PROXMOX_NODE_NAME (dev)"

if $SET_TOKEN; then
  echo "Paste API token secret for nested PVE:"
  read -rs TOKEN
  printf '%s' "$TOKEN" | gh secret set PROXMOX_API_TOKEN_SECRET --env dev --repo "$REPO" --body -
  unset TOKEN
  echo "set PROXMOX_API_TOKEN_SECRET (dev)"
fi

echo ""
echo "Next: infra-plan-dev.yml on push homelab-v2, or locally:"
echo "  cd terraform && terraform init -backend=false"
echo "  terraform plan -state=environments/dev/terraform.tfstate -var-file=environments/dev/terraform.tfvars"
