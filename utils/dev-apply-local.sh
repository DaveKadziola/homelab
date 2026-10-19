#!/usr/bin/env bash
# Local terraform apply for nested Proxmox (dev).
# Requires: nested PVE up, token in ~/.homelab-pve-dev-token-secret (or env).
#
# Usage: ./utils/dev-apply-local.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

./utils/ensure-dev-proxmox.sh

IP="${DEV_PROXMOX_IP:-192.168.122.219}"
PASS_FILE="${HOME}/.homelab-pve-dev-root-pass"
TOKEN_FILE="${HOME}/.homelab-pve-dev-token-secret"

export TF_VAR_environment=dev
export TF_VAR_proxmox_node_name="${TF_VAR_proxmox_node_name:-dev}"
export TF_VAR_proxmox_api_url="${TF_VAR_proxmox_api_url:-https://${IP}:8006/api2/json}"
export TF_VAR_proxmox_api_token_id="${TF_VAR_proxmox_api_token_id:-root@pam!terraform}"
export TF_VAR_proxmox_ssh_username="${TF_VAR_proxmox_ssh_username:-root}"

if [[ -z "${TF_VAR_proxmox_api_token_secret:-}" && -f "$TOKEN_FILE" ]]; then
  export TF_VAR_proxmox_api_token_secret="$(cat "$TOKEN_FILE")"
fi
if [[ -z "${TF_VAR_proxmox_ssh_password:-}" && -f "$PASS_FILE" ]]; then
  export TF_VAR_proxmox_ssh_password="$(cat "$PASS_FILE")"
fi

if [[ -z "${TF_VAR_proxmox_api_token_secret:-}" ]]; then
  echo "ERROR: missing API token secret (${TOKEN_FILE} or TF_VAR_proxmox_api_token_secret)"
  exit 1
fi

if [[ -z "${TF_VAR_ubuntu_docker_ssh_pub:-}" && -f "${HOME}/.ssh/homelab_dev_ed25519.pub" ]]; then
  export TF_VAR_ubuntu_docker_ssh_pub="$(cat "${HOME}/.ssh/homelab_dev_ed25519.pub")"
fi

if [[ -z "${TF_VAR_ubuntu_docker_password:-}" ]]; then
  if [[ ! -f "${HOME}/.homelab-ubuntu-apps-dev-pass" ]]; then
    PLAIN=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
    printf '%s\n' "$PLAIN" > "${HOME}/.homelab-ubuntu-apps-dev-pass"
    chmod 600 "${HOME}/.homelab-ubuntu-apps-dev-pass"
    echo "Generated ubuntu password -> ~/.homelab-ubuntu-apps-dev-pass"
  fi
  # Fixed salt: a fresh openssl salt on every run looks like cloud-init drift
  # and the Proxmox provider then wants to destroy the VM.
  PLAIN="$(cat "${HOME}/.homelab-ubuntu-apps-dev-pass")"
  SALT="$(printf '%s' "$PLAIN" | sha256sum | cut -c1-16)"
  export TF_VAR_ubuntu_docker_password="$(openssl passwd -6 -salt "$SALT" "$PLAIN")"
fi

cd terraform

# State lives in HCP Terraform (workspace homelab-dev, execution mode local); needs
# `terraform login` once on this machine.
export TF_WORKSPACE=homelab-dev
rm -rf .terraform
terraform init -input=false

terraform plan -input=false -var-file=environments/dev/terraform.tfvars -out=environments/dev/plan.tfplan
terraform apply environments/dev/plan.tfplan

echo "Done. SSH: ssh -i ~/.ssh/homelab_dev_ed25519 ubuntu-dev@192.168.122.50"
echo "Password: cat ~/.homelab-ubuntu-apps-dev-pass"
