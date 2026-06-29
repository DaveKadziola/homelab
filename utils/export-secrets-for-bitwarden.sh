#!/usr/bin/env bash
# Export homelab credentials to a text file for Bitwarden Secure Notes.
#
# GitHub Secrets are WRITE-ONLY — values already in GH cannot be read back.
# This script exports:
#   - local files (SSH key, Terraform token)
#   - GitHub Environment variables (readable via API)
#   - with --regenerate: NEW random values for GH-only secrets (then re-run
#     bootstrap-f1-secrets.sh or gh secret set to sync GH with Bitwarden)
#
# Usage:
#   ./utils/export-secrets-for-bitwarden.sh
#   ./utils/export-secrets-for-bitwarden.sh -o ~/homelab-bitwarden.txt
#   ./utils/export-secrets-for-bitwarden.sh --regenerate
#
# After pasting into Bitwarden, delete the file:
#   shred -u ~/homelab-bitwarden-*.txt

set -euo pipefail

REPO="${GITHUB_REPO:-DaveKadziola/homelab}"
SSH_KEY="${HOME}/.ssh/homelab_dev_ed25519"
TFRC="${HOME}/.terraform.d/credentials.tfrc.json"
OUTPUT=""
REGENERATE=false

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output) OUTPUT="$2"; shift 2 ;;
    --regenerate) REGENERATE=true; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

OUTPUT="${OUTPUT:-${HOME}/homelab-bitwarden-$(date +%Y%m%d-%H%M%S).txt}"

command -v gh >/dev/null || { echo "gh CLI required" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh not authenticated" >&2; exit 1; }

rand() { openssl rand -base64 32; }

umask 077
mkdir -p "$(dirname "$OUTPUT")"

# name|env|value|source
declare -a ENTRIES=()

add_entry() {
  local bw_path="$1" value="$2" source="$3"
  ENTRIES+=("${bw_path}|${value}|${source}")
}

gh_var() {
  local name="$1" env="$2"
  gh variable list --env "$env" --repo "$REPO" \
    --json name,value \
    --jq ".[] | select(.name==\"${name}\") | .value" 2>/dev/null | head -1
}

gh_secret_exists() {
  local name="$1" env="$2"
  gh secret list --env "$env" --repo "$REPO" --json name --jq ".[] | select(.name==\"$name\") | .name" 2>/dev/null | grep -q .
}

# --- Local: SSH (dev) ---
if [[ -f "$SSH_KEY" ]]; then
  add_entry "homelab/UBUNTU_DOCKER_SSH_PRIV/dev" "$(cat "$SSH_KEY")" "local: ${SSH_KEY}"
  add_entry "homelab/UBUNTU_DOCKER_SSH_PUB/dev" "$(cat "${SSH_KEY}.pub")" "local: ${SSH_KEY}.pub"
else
  add_entry "homelab/UBUNTU_DOCKER_SSH_PRIV/dev" "" "MISSING: ${SSH_KEY} not found"
fi

# --- Local: Terraform API token ---
if [[ -f "$TFRC" ]]; then
  TF_TOKEN=$(python3 -c "
import json, sys
try:
    print(json.load(open('${TFRC}'))['credentials']['app.terraform.io']['token'])
except (KeyError, FileNotFoundError):
    sys.exit(1)
" 2>/dev/null) || TF_TOKEN=""
  if [[ -n "$TF_TOKEN" ]]; then
    add_entry "homelab/TF_API_TOKEN/prod" "$TF_TOKEN" "local: ${TFRC}"
  else
    add_entry "homelab/TF_API_TOKEN/prod" "" "MISSING: token not in ${TFRC}"
  fi
  unset TF_TOKEN
else
  add_entry "homelab/TF_API_TOKEN/prod" "" "MISSING: ${TFRC} not found"
fi

# --- GH variables (readable) ---
for env in dev prod; do
  for var in PROXMOX_API_URL PROXMOX_API_TOKEN_ID PROXMOX_SSH_USERNAME UBUNTU_DOCKER_SSH_PUB; do
    val=$(gh_var "$var" "$env")
    if [[ -n "$val" ]]; then
      add_entry "homelab/${var}/${env} (GitHub variable)" "$val" "gh variable ${env}/${var}"
    elif gh secret list --env "$env" --repo "$REPO" --json name --jq '.[].name' 2>/dev/null | grep -q .; then
      add_entry "homelab/${var}/${env} (GitHub variable)" "" "NOT SET in GH env ${env}"
    fi
  done
done

# --- GH secrets (not readable — regenerate or placeholder) ---
SECRET_NAMES=(
  POSTGRES_PASSWORD
  PROXMOX_API_TOKEN_SECRET
  PROXMOX_SSH_PASSWORD
  UBUNTU_DOCKER_PASSWORD
  UBUNTU_DOCKER_SSH_PRIV
)

for env in dev prod; do
  for name in "${SECRET_NAMES[@]}"; do
    # Skip if already filled from local
    if [[ "$name" == "UBUNTU_DOCKER_SSH_PRIV" && "$env" == "dev" && -f "$SSH_KEY" ]]; then
      continue
    fi

    if ! gh_secret_exists "$name" "$env"; then
      continue
    fi

    if $REGENERATE; then
      if [[ "$name" == "UBUNTU_DOCKER_SSH_PRIV" ]]; then
        if [[ -f "$SSH_KEY" ]]; then
          add_entry "homelab/${name}/${env}" "$(cat "$SSH_KEY")" "local copy (regenerate mode; prod may need separate key at F3)"
        else
          add_entry "homelab/${name}/${env}" "" "MISSING: generate SSH key first"
        fi
      else
        add_entry "homelab/${name}/${env}" "$(rand)" "NEW random (--regenerate); sync to GH with gh secret set"
      fi
    else
      add_entry "homelab/${name}/${env}" "" "UNREADABLE from GitHub (write-only). Use --regenerate for new value, or keep GH as-is without Bitwarden copy"
    fi
  done
done

# TF_API_TOKEN prod — if only in GH, already handled via local; if missing local note
if [[ -f "$TFRC" ]]; then
  : # already added
elif gh_secret_exists "TF_API_TOKEN" "prod"; then
  if $REGENERATE; then
    add_entry "homelab/TF_API_TOKEN/prod" "" "UNREADABLE from GH; get token from app.terraform.io → User Settings → Tokens"
  else
    add_entry "homelab/TF_API_TOKEN/prod" "" "UNREADABLE from GitHub; copy from app.terraform.io or ${TFRC}"
  fi
fi

# --- Write file ---
{
  echo "Homelab secrets export for Bitwarden"
  echo "Generated: $(date -Iseconds)"
  echo "Repo: ${REPO}"
  echo "Regenerate mode: ${REGENERATE}"
  echo ""
  echo "Paste each block below as a Bitwarden Secure Note in folder: homelab"
  echo "Name = line after ===== (e.g. homelab/POSTGRES_PASSWORD/dev)"
  echo "Notes = value line(s) below the title"
  echo ""
  if ! $REGENERATE; then
    echo "NOTE: GitHub Secrets cannot be read back. Entries with empty value"
    echo "      need --regenerate (new passwords) OR accept GH-only storage."
    echo ""
  else
    echo "NOTE: --regenerate created NEW passwords for GH-only secrets."
    echo "      Update GitHub to match Bitwarden:"
    echo "        ./utils/bootstrap-f1-secrets.sh   # or manual gh secret set"
    echo ""
  fi

  for entry in "${ENTRIES[@]}"; do
    IFS='|' read -r bw_path value source <<< "$entry"
    echo "========================================"
    echo "${bw_path}"
    echo "Source: ${source}"
    echo "----------------------------------------"
    if [[ -n "$value" ]]; then
      echo "${value}"
    else
      echo "(no value — see Source)"
    fi
    echo ""
  done

  echo "========================================"
  echo "END — delete this file after Bitwarden import"
  echo "  shred -u '${OUTPUT}'"
  echo "========================================"
} > "$OUTPUT"

chmod 600 "$OUTPUT"

echo "Saved: ${OUTPUT}"
echo "Entries: ${#ENTRIES[@]}"
if ! $REGENERATE; then
  unreadable=0
  for entry in "${ENTRIES[@]}"; do
    IFS='|' read -r _ value _ <<< "$entry"
    [[ -z "$value" ]] && ((unreadable++)) || true
  done
  if [[ "$unreadable" -gt 0 ]]; then
    echo "Warning: ${unreadable} entries have no value (GH secrets are write-only)."
    echo "Re-run with --regenerate to generate new passwords for Bitwarden."
  fi
fi
