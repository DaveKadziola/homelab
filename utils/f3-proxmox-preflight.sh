#!/usr/bin/env bash
# F3 preflight — Proxmox API reachability + list VMs (conflicts with TF vm_id 101/102).
#
# Usage:
#   export TF_VAR_proxmox_api_url=https://192.168.20.20:8006/api2/json
#   export TF_VAR_proxmox_api_token_id='terraform-prov@pam!terraform'
#   export TF_VAR_proxmox_api_token_secret='...'
#   ./utils/f3-proxmox-preflight.sh
#
# Or load from gh (prod env) — secrets not printed.

set -euo pipefail

API_URL="${TF_VAR_proxmox_api_url:-${PROXMOX_API_URL:-https://192.168.20.20:8006/api2/json}}"
TOKEN_ID="${TF_VAR_proxmox_api_token_id:-}"
TOKEN_SECRET="${TF_VAR_proxmox_api_token_secret:-}"
NODE="${TF_VAR_proxmox_node_name:-proxmox}"
REPO="${GITHUB_REPO:-DaveKadziola/homelab}"

if [[ -z "$TOKEN_ID" || -z "$TOKEN_SECRET" ]]; then
  if command -v gh &>/dev/null; then
    TOKEN_ID=$(gh variable get PROXMOX_API_TOKEN_ID --env prod --repo "$REPO" 2>/dev/null || true)
  fi
fi

echo "=== F3 Proxmox preflight ($(date -Iseconds)) ==="
echo "API: $API_URL"
echo "Node: $NODE"
echo ""

if ! curl -fsSk --max-time 5 "${API_URL%/api2/json}/" &>/dev/null; then
  echo "FAIL: Proxmox HTTPS not reachable — power on host at 192.168.20.20"
  exit 1
fi
echo "OK   Proxmox HTTPS reachable"

if [[ -z "$TOKEN_ID" || -z "$TOKEN_SECRET" ]]; then
  echo "WARN: API token secret not in env — export TF_VAR_proxmox_api_token_secret"
  exit 0
fi

AUTH_HEADER="Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}"
RESP=$(curl -fsSk --max-time 15 -H "$AUTH_HEADER" "${API_URL}/nodes/${NODE}/qemu" 2>&1) || {
  echo "FAIL: API /nodes/${NODE}/qemu — check token and node name (proxmox_node_name)"
  exit 1
}

echo "OK   API token works"
echo ""
echo "--- VMs on node ${NODE} ---"
python3 -c "
import json, sys
data = json.loads(sys.argv[1])
planned = {101: 'ubuntu-apps-prod', 102: 'ubuntu-nas-prod'}
if not data:
    print('(no VMs)')
else:
    for vm in sorted(data, key=lambda x: int(x.get('vmid', 0))):
        vid = int(vm['vmid'])
        name = vm.get('name', '?')
        status = vm.get('status', '?')
        tag = ' *** CONFLICT with TF vm_id' if vid in planned else ''
        print(f\"  {vid:>4}  {status:10}  {name}{tag}\")
print()
print('TF will create vm_id 101 (ubuntu-apps) and 102 (ubuntu-nas).')
print('Remove or rename conflicting VMs in Proxmox UI before apply.')
" "$RESP"
