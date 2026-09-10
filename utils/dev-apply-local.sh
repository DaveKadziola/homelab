#!/usr/bin/env bash
# Local terraform apply for nested Proxmox (dev).
# Requires: nested PVE up, real API token (not F1 placeholder).
#
# Usage:
#   export TF_VAR_proxmox_api_token_secret='...'   # from PVE UI or Bitwarden
#   export TF_VAR_proxmox_ssh_password='...'        # root password (provider SSH)
#   ./utils/dev-apply-local.sh
#
# Optional: TF_VAR_ubuntu_docker_password (SHA-512 hash), TF_VAR_ubuntu_docker_ssh_pub

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

./utils/ensure-dev-proxmox.sh

IP="${DEV_PROXMOX_IP:-}"
if [[ -z "$IP" ]]; then
  IP=$(ip neigh show | awk '/52:54:00:a9:32:90/ {print $1; exit}')
fi
IP="${IP:-192.168.122.219}"

export TF_VAR_environment=dev
export TF_VAR_proxmox_node_name="${TF_VAR_proxmox_node_name:-dev}"
export TF_VAR_proxmox_api_url="${TF_VAR_proxmox_api_url:-https://${IP}:8006/api2/json}"
export TF_VAR_proxmox_api_token_id="${TF_VAR_proxmox_api_token_id:-root@pam!terraform}"
export TF_VAR_proxmox_ssh_username="${TF_VAR_proxmox_ssh_username:-root}"

if [[ -z "${TF_VAR_proxmox_api_token_secret:-}" ]]; then
  echo "ERROR: set TF_VAR_proxmox_api_token_secret"
  echo "  UI: https://${IP}:8006 → Datacenter → Permissions → API Tokens"
  echo "  Create token for root@pam (Privilege Separation OFF for bootstrap)"
  exit 1
fi

if [[ -z "${TF_VAR_proxmox_ssh_password:-}" ]]; then
  echo "WARN: TF_VAR_proxmox_ssh_password unset — provider SSH may fail for some resources"
fi

if [[ -z "${TF_VAR_ubuntu_docker_ssh_pub:-}" && -f "${HOME}/.ssh/homelab_dev_ed25519.pub" ]]; then
  export TF_VAR_ubuntu_docker_ssh_pub="$(cat "${HOME}/.ssh/homelab_dev_ed25519.pub")"
fi

if [[ -z "${TF_VAR_ubuntu_docker_password:-}" ]]; then
  # cloud-init password field — generate hash for "changeme" only if unset (override!)
  export TF_VAR_ubuntu_docker_password="$(openssl passwd -6 -salt homelab "changeme")"
  echo "WARN: using temporary ubuntu password hash for 'changeme' — change after first login"
fi

cd terraform
terraform init -backend=false -reconfigure
terraform plan \
  -state=environments/dev/terraform.tfstate \
  -var-file=environments/dev/terraform.tfvars \
  -out=environments/dev/plan.tfplan
terraform apply -state=environments/dev/terraform.tfstate environments/dev/plan.tfplan

echo "Done. SSH: ssh -i ~/.ssh/homelab_dev_ed25519 ubuntu-dev@192.168.122.50"
