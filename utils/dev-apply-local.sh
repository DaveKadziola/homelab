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
  if [[ -f "${HOME}/.homelab-ubuntu-apps-dev-pass" ]]; then
    export TF_VAR_ubuntu_docker_password="$(openssl passwd -6 "$(cat "${HOME}/.homelab-ubuntu-apps-dev-pass")")"
  else
    PLAIN=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
    printf '%s\n' "$PLAIN" > "${HOME}/.homelab-ubuntu-apps-dev-pass"
    chmod 600 "${HOME}/.homelab-ubuntu-apps-dev-pass"
    export TF_VAR_ubuntu_docker_password="$(openssl passwd -6 "$PLAIN")"
    echo "Generated ubuntu password -> ~/.homelab-ubuntu-apps-dev-pass"
  fi
fi

cd terraform

# Disable HCP Terraform cloud block for local state
CLOUD_OFF=0
if [[ -f cloud.tf ]]; then
  mv cloud.tf cloud.tf.off
  CLOUD_OFF=1
fi
restore_cloud() {
  if [[ "$CLOUD_OFF" -eq 1 && -f cloud.tf.off ]]; then
    mv cloud.tf.off cloud.tf
  fi
}
trap restore_cloud EXIT

rm -rf .terraform
terraform init -reconfigure

STATE="environments/dev/terraform.tfstate"
terraform plan -state="$STATE" -var-file=environments/dev/terraform.tfvars -out=environments/dev/plan.tfplan
terraform apply -state="$STATE" environments/dev/plan.tfplan

echo "Done. SSH: ssh -i ~/.ssh/homelab_dev_ed25519 ubuntu-dev@192.168.122.50"
echo "Password: cat ~/.homelab-ubuntu-apps-dev-pass"
