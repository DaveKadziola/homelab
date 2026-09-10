#!/usr/bin/env bash
# Generate application credentials declared in config/identities.yml (F7-A).
#
# Values are written to:
#   - GitHub Environment secret (write-only, used by CI)
#   - a staging file for Bitwarden import (chmod 600, delete after import)
#   - a local cache under ~/.homelab-secrets/<env>/ for local Ansible runs
#
# Values are never printed to stdout.
#
# Usage:
#   ./utils/gen-app-credentials.sh --env dev --all
#   ./utils/gen-app-credentials.sh --env prod --app immich
#   ./utils/gen-app-credentials.sh --env dev --secret POSTGRES_PASSWORD --rotate
#   ./utils/gen-app-credentials.sh --env dev --all --dry-run
#
# Existing secrets are skipped unless --rotate is given.

set -euo pipefail

REPO="${GITHUB_REPO:-DaveKadziola/homelab}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITIES="${ROOT}/config/identities.yml"
INVENTORY="${ROOT}/docs/secrets-inventory.md"
CACHE_ROOT="${HOME}/.homelab-secrets"

ENVIRONMENT=""
TARGET_APP=""
TARGET_SECRET=""
ALL=false
ROTATE=false
DRY_RUN=false
OUTPUT=""

usage() {
  sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENVIRONMENT="$2"; shift 2 ;;
    --app) TARGET_APP="$2"; shift 2 ;;
    --secret) TARGET_SECRET="$2"; shift 2 ;;
    --all) ALL=true; shift ;;
    --rotate) ROTATE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -o|--output) OUTPUT="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

[[ -n "$ENVIRONMENT" ]] || { echo "--env dev|prod is required" >&2; exit 1; }
[[ "$ENVIRONMENT" == "dev" || "$ENVIRONMENT" == "prod" ]] || { echo "--env must be dev or prod" >&2; exit 1; }
$ALL || [[ -n "$TARGET_APP" || -n "$TARGET_SECRET" ]] || { echo "Pass --all, --app or --secret" >&2; exit 1; }
[[ -f "$IDENTITIES" ]] || { echo "Missing ${IDENTITIES}" >&2; exit 1; }
command -v gh >/dev/null || { echo "gh CLI required" >&2; exit 1; }
$DRY_RUN || gh auth status >/dev/null 2>&1 || { echo "gh not authenticated" >&2; exit 1; }

# name|app|login|identity|email|username|format|inject
mapfile -t RECORDS < <(
  python3 - "$IDENTITIES" "$ENVIRONMENT" "$TARGET_APP" "$TARGET_SECRET" <<'PY'
import sys, yaml

path, environment, want_app, want_secret = sys.argv[1:5]
doc = yaml.safe_load(open(path))
identities = doc.get("identities", {})
env_email = doc.get("environment_email", {}).get(environment, "")
rows = []


def email_for(ident):
    value = ident.get("email", "")
    return env_email if value == "environment" else value

for account in doc.get("accounts", []):
    if environment not in account.get("envs", []):
        continue
    secret = account.get("secret")
    if not secret:
        continue
    ident = identities.get(account.get("identity"), {})
    rows.append([
        secret,
        account.get("app", ""),
        account.get("login", "none"),
        account.get("identity", ""),
        email_for(ident),
        ident.get("username", ""),
        "password",
        account.get("inject", "env"),
    ])

for secret in doc.get("service_secrets", []):
    if environment not in secret.get("envs", []):
        continue
    if secret.get("issued_by"):
        continue  # issued by another app, not generated here
    used_by = secret.get("used_by", [])
    rows.append([
        secret["name"],
        used_by[0] if used_by else "",
        "none",
        "",
        "",
        "",
        secret.get("format", "password"),
        "env",
    ])

for row in rows:
    if want_secret and row[0] != want_secret:
        continue
    if want_app and row[1] != want_app:
        continue
    print("|".join(row))
PY
)

[[ ${#RECORDS[@]} -gt 0 ]] || { echo "No matching secrets in config/identities.yml" >&2; exit 1; }

OUTPUT="${OUTPUT:-${HOME}/homelab-bitwarden-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).txt}"
CACHE_DIR="${CACHE_ROOT}/${ENVIRONMENT}"

umask 077
$DRY_RUN || mkdir -p "$CACHE_DIR" "$(dirname "$OUTPUT")"

gen_value() {
  case "$1" in
    hex64) openssl rand -hex 32 ;;
    *) openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32 ;;
  esac
}

secret_exists() {
  gh secret list --env "$ENVIRONMENT" --repo "$REPO" --json name --jq ".[] | select(.name==\"$1\") | .name" 2>/dev/null | grep -q .
}

created=0
rotated=0
skipped=0
declare -a STAGED=()

for record in "${RECORDS[@]}"; do
  IFS='|' read -r name app login identity email username format inject <<< "$record"

  if secret_exists "$name" && ! $ROTATE; then
    skipped=$((skipped + 1))
    continue
  fi

  action="create"
  secret_exists "$name" && action="rotate"

  if $DRY_RUN; then
    echo "[dry-run] ${action} ${name} (env=${ENVIRONMENT} app=${app:-–} inject=${inject})"
    continue
  fi

  value="$(gen_value "$format")"
  printf '%s' "$value" | gh secret set "$name" --env "$ENVIRONMENT" --repo "$REPO" --body -
  printf '%s' "$value" > "${CACHE_DIR}/${name}"
  chmod 600 "${CACHE_DIR}/${name}"

  login_hint="n/a"
  case "$login" in
    email) login_hint="$email" ;;
    username) login_hint="$username" ;;
  esac

  STAGED+=("homelab/${name}/${ENVIRONMENT}|${value}|app=${app:-–} login=${login_hint} inject=${inject}")
  unset value

  if [[ "$action" == "rotate" ]]; then
    rotated=$((rotated + 1))
  else
    created=$((created + 1))
  fi
done

if $DRY_RUN; then
  echo "Dry run only — nothing written. Existing secrets skipped: ${skipped}"
  exit 0
fi

if [[ ${#STAGED[@]} -gt 0 ]]; then
  {
    echo "Homelab credentials — environment: ${ENVIRONMENT}"
    echo "Generated: $(date -Iseconds)"
    echo "Repo: ${REPO}"
    echo ""
    echo "Paste each block as a Bitwarden Secure Note in folder: homelab"
    echo ""
    for entry in "${STAGED[@]}"; do
      IFS='|' read -r bw_path value meta <<< "$entry"
      echo "========================================"
      echo "${bw_path}"
      echo "Context: ${meta}"
      echo "----------------------------------------"
      echo "${value}"
      echo ""
    done
    echo "========================================"
    echo "END — delete after Bitwarden import:  shred -u '${OUTPUT}'"
  } > "$OUTPUT"
  chmod 600 "$OUTPUT"

  # Inventory keeps names and dates only, never values.
  today="$(date +%F)"
  for entry in "${STAGED[@]}"; do
    IFS='|' read -r bw_path _ _ <<< "$entry"
    name="${bw_path#homelab/}"
    name="${name%%/*}"
    if grep -q "| \`${name}\` | ${ENVIRONMENT} |" "$INVENTORY" 2>/dev/null; then
      python3 - "$INVENTORY" "$name" "$ENVIRONMENT" "$today" <<'PY'
import re, sys
path, name, env, today = sys.argv[1:5]
text = open(path).read()
pattern = re.compile(rf"(\| `{re.escape(name)}` \| {re.escape(env)} \|[^\n]*?)(rotated [0-9-]{{10}})?(\s*\|\s*)$", re.M)
text, count = pattern.subn(lambda m: f"{m.group(1)}rotated {today}{m.group(3)}", text)
if count:
    open(path, "w").write(text)
PY
    else
      printf '| `%s` | %s | secret | homelab/%s/%s | set | generated %s |\n' \
        "$name" "$ENVIRONMENT" "$name" "$ENVIRONMENT" "$today" >> "$INVENTORY"
    fi
  done
fi

echo "Environment: ${ENVIRONMENT}"
echo "Created: ${created}  Rotated: ${rotated}  Skipped (already set): ${skipped}"
if [[ ${#STAGED[@]} -gt 0 ]]; then
  echo "Bitwarden staging file: ${OUTPUT}  (shred it after import)"
  echo "Local cache for Ansible: ${CACHE_DIR}"
  echo "Inventory updated: docs/secrets-inventory.md"
  echo ""
  echo "Next: apply them to the apps"
  echo "  ansible-playbook -i ansible/environments/${ENVIRONMENT}/hosts.ini ansible/playbooks/deploy-core.yml"
  echo "  ./utils/bootstrap-apps.sh --env ${ENVIRONMENT}"
fi
