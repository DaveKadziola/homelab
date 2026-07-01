#!/usr/bin/env bash
# Collect MAC addresses for F2-07 / docs/network.md (run from laptop).
#
# Usage:
#   ./utils/collect-homelab-macs.sh
#   PROXMOX_HOST=192.168.20.10 ./utils/collect-homelab-macs.sh

set -euo pipefail

PROXMOX_HOST="${PROXMOX_HOST:-192.168.20.10}"
PROXMOX_USER="${PROXMOX_USER:-root}"

echo "=== Homelab MAC collection (F2-07) ==="
echo ""
echo "Local interfaces:"
ip -br link | grep -v 'lo\|virbr\|docker\|br-\|vnet\|wwan' || ip link show
echo ""

if ssh -o BatchMode=yes -o ConnectTimeout=3 "${PROXMOX_USER}@${PROXMOX_HOST}" exit 2>/dev/null; then
  echo "Proxmox (${PROXMOX_HOST}) interfaces:"
  ssh "${PROXMOX_USER}@${PROXMOX_HOST}" 'ip -br link'
else
  echo "Proxmox SSH not available at ${PROXMOX_HOST} — collect MACs from:"
  echo "  - Proxmox UI → Node → Network"
  echo "  - OPNsense → Services → DHCPv4 → Leases"
  echo "  - HP T620 HAOS console"
fi
echo ""
echo "Update docs/network.md and OPNsense DHCP static mappings."
echo "Placeholder MACs: aa:bb:cc:dd:ee:01 … ee:04"
