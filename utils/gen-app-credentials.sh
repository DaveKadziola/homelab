#!/usr/bin/env bash
# Generate application credentials declared in config/identities.yml (F7-A).
#
# Values are written to:
#   - GitHub Environment secret (write-only, used by CI)
#   - a local cache under ~/.homelab-secrets/<env>/ for local Ansible runs
#   - Bitwarden homelab/<NAME>/<env> through utils/bw-store.py when BW_SESSION is
#     unlocked; otherwise the names are queued for utils/bw-store.py --pending
#
# Values are never printed to stdout.
#
# Usage:
#   ./utils/gen-app-credentials.sh --env dev --all
#   ./utils/gen-app-credentials.sh --env prod --app immich
#   ./utils/gen-app-credentials.sh --env dev --secret POSTGRES_PASSWORD --rotate
#   ./utils/gen-app-credentials.sh --env dev --all --dry-run
#   ./utils/gen-app-credentials.sh --env dev --secret VSUM_GIT_TOKEN --paste
#
# Existing secrets are skipped unless --rotate is given. --paste reads the value of one
# secret from the terminal (hidden) instead of generating it, also for a secret an issuer
# makes (issued_by in config/identities.yml), and stores it the same three ways.

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
PASTE=false

usage() {
  sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
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
    --paste) PASTE=true; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

[[ -n "$ENVIRONMENT" ]] || { echo "--env dev|prod is required" >&2; exit 1; }
[[ "$ENVIRONMENT" == "dev" || "$ENVIRONMENT" == "prod" ]] || { echo "--env must be dev or prod" >&2; exit 1; }
$ALL || [[ -n "$TARGET_APP" || -n "$TARGET_SECRET" ]] || { echo "Pass --all, --app or --secret" >&2; exit 1; }
! $PASTE || { [[ -n "$TARGET_SECRET" && -z "$TARGET_APP" ]] && ! $ALL; } || { echo "--paste takes one --secret" >&2; exit 1; }
[[ -f "$IDENTITIES" ]] || { echo "Missing ${IDENTITIES}" >&2; exit 1; }
command -v gh >/dev/null || { echo "gh CLI required" >&2; exit 1; }
$DRY_RUN || gh auth status >/dev/null 2>&1 || { echo "gh not authenticated" >&2; exit 1; }

# name|app|login|identity|email|username|format|inject
mapfile -t RECORDS < <(
  python3 - "$IDENTITIES" "$ENVIRONMENT" "$TARGET_APP" "$TARGET_SECRET" "$PASTE" <<'PY'
import sys, yaml

path, environment, want_app, want_secret, paste = sys.argv[1:6]
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
    if secret.get("issued_by") and not (paste == "true" and secret["name"] == want_secret):
        continue  # issued by another app, not generated here; --paste takes its value
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

CACHE_DIR="${CACHE_ROOT}/${ENVIRONMENT}"

umask 077
$DRY_RUN || mkdir -p "$CACHE_DIR"

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
# On exit, also after a failed gh call: a value already in the cache must reach Bitwarden or the
# queue, because a re-run skips it as "already set".
trap '[[ ${#STAGED[@]} -eq 0 ]] || "${ROOT}/utils/bw-store.py" --env "$ENVIRONMENT" "${STAGED[@]}"' EXIT

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

  if $PASTE; then
    # read drops leading and trailing blanks; || true keeps a piped value without a newline.
    read -rs -p "Paste ${name} for ${ENVIRONMENT} (hidden): " value || true
    [[ ! -t 0 ]] || echo >&2
    [[ -n "$value" ]] || { echo "Empty value for ${name}: nothing written" >&2; exit 1; }
  else
    value="$(gen_value "$format")"
  fi
  printf '%s' "$value" | gh secret set "$name" --env "$ENVIRONMENT" --repo "$REPO"
  printf '%s' "$value" > "${CACHE_DIR}/${name}"
  chmod 600 "${CACHE_DIR}/${name}"
  STAGED+=("$name")
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
  # Inventory keeps names and dates only, never values.
  today="$(date +%F)"
  for name in "${STAGED[@]}"; do
    if grep -q "| \`${name}\` | ${ENVIRONMENT} |" "$INVENTORY" 2>/dev/null; then
      python3 - "$INVENTORY" "$name" "$ENVIRONMENT" "$today" "$PASTE" <<'PY'
import re, sys
path, name, env, today, paste = sys.argv[1:6]
text = open(path).read()
if paste == "true":
    # A pasted secret was usually "planned": mark it set and keep its notes.
    head = f"| `{name}` | {env} |"
    lines = text.splitlines(keepends=True)
    for i, line in enumerate(lines):
        if line.startswith(head):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            cells[4] = "set"
            notes = re.sub(r";? ?pasted [0-9-]{10}$", "", cells[5]).strip()
            cells[5] = f"{notes}; pasted {today}" if notes else f"pasted {today}"
            lines[i] = "| " + " | ".join(cells) + " |\n"
    open(path, "w").write("".join(lines))
    raise SystemExit
pattern = re.compile(rf"(\| `{re.escape(name)}` \| {re.escape(env)} \|[^\n]*?)(rotated [0-9-]{{10}})?(\s*\|\s*)$", re.M)
def rotated(m):
    # Same form as the hand-written rows: "<notes>; rotated <date>".
    notes = m.group(1).rstrip().rstrip(";").rstrip()
    sep = " " if notes.endswith("|") else "; "
    return f"{notes}{sep}rotated {today}{m.group(3)}"
text, count = pattern.subn(rotated, text)
if count:
    open(path, "w").write(text)
PY
    else
      python3 - "$INVENTORY" "$name" "$ENVIRONMENT" "$today" "$PASTE" <<'PY'
import sys
path, name, env, today, paste = sys.argv[1:6]
marker = "## GitHub Environments — variables"
how = "pasted" if paste == "true" else "generated"
row = f"| `{name}` | {env} | secret | `homelab/{name}/{env}` | set | {how} {today} |\n"
text = open(path).read()
if row in text:
    raise SystemExit
if marker not in text:
    open(path, "a").write(row)
    raise SystemExit
head, tail = text.split(marker, 1)
# After the last row of the secrets table, above the --- that closes it.
last = head.rstrip().rfind("\n|")
end = head.index("\n", last + 1) + 1 if last >= 0 else len(head)
open(path, "w").write(head[:end] + row + head[end:] + marker + tail)
PY
    fi
  done
fi

echo "Environment: ${ENVIRONMENT}"
echo "Created: ${created}  Rotated: ${rotated}  Skipped (already set): ${skipped}"
if [[ ${#STAGED[@]} -gt 0 ]]; then
  echo "Local cache for Ansible: ${CACHE_DIR}"
  echo "Inventory updated: docs/secrets-inventory.md"
  echo ""
  echo "Next: apply them to the apps"
  echo "  ansible-playbook -i ansible/environments/${ENVIRONMENT}/hosts.ini ansible/playbooks/deploy-core.yml"
  echo "  ./utils/bootstrap-apps.sh --env ${ENVIRONMENT}"
fi
