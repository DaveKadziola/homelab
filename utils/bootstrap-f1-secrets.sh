#!/usr/bin/env bash
# Bootstrap F1 GitHub secrets/variables (generate → gh; copy values to Bitwarden manually).
# Does not print secret values.
#
# Prefer: ./utils/export-secrets-for-bitwarden.sh --regenerate  (save to txt → Bitwarden)
#         then sync GH if you regenerated new passwords.
set -euo pipefail

REPO="${GITHUB_REPO:-DaveKadziola/homelab}"
SSH_KEY="${HOME}/.ssh/homelab_dev_ed25519"

rand() { openssl rand -base64 32; }

set_secret() {
  local name="$1" env="$2" value="$3"
  printf '%s' "$value" | gh secret set "$name" --env "$env" --repo "$REPO" --body -
  echo "set secret ${name} (${env})"
}

set_var() {
  local name="$1" env="$2" value="$3"
  gh variable set "$name" --env "$env" --repo "$REPO" --body "$value"
  echo "set variable ${name} (${env})"
}

command -v gh >/dev/null || { echo "gh required"; exit 1; }
command -v openssl >/dev/null || { echo "openssl required"; exit 1; }

# Dev SSH key for ubuntu-apps / dev VM
if [[ ! -f "$SSH_KEY" ]]; then
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "homelab-dev"
fi

for env in dev prod; do
  set_secret POSTGRES_PASSWORD "$env" "$(rand)"
  set_secret PROXMOX_API_TOKEN_SECRET "$env" "$(rand)"
  set_secret PROXMOX_SSH_PASSWORD "$env" "$(rand)"
  set_secret UBUNTU_DOCKER_PASSWORD "$env" "$(rand)"
  set_var PROXMOX_API_URL "$env" "https://proxmox.example:8006/api2/json"
  set_var PROXMOX_API_TOKEN_ID "$env" "homelab-${env}@pam!terraform"
  set_var PROXMOX_SSH_USERNAME "$env" "root"
done

set_secret UBUNTU_DOCKER_SSH_PRIV dev "$(cat "$SSH_KEY")"
set_var UBUNTU_DOCKER_SSH_PUB dev "$(cat "${SSH_KEY}.pub")"

# Prod-only: copy from local terraform login (not echoed)
if [[ -f "${HOME}/.terraform.d/credentials.tfrc.json" ]]; then
  TF_TOKEN=$(python3 -c "import json; print(json.load(open('${HOME}/.terraform.d/credentials.tfrc.json'))['credentials']['app.terraform.io']['token'])")
  set_secret TF_API_TOKEN prod "$TF_TOKEN"
  unset TF_TOKEN
else
  echo "WARN: no credentials.tfrc.json — set TF_API_TOKEN/prod manually"
fi

echo "Done. Store each value in Bitwarden homelab/<NAME>/<env> (values not shown)."
