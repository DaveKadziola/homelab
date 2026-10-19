#!/usr/bin/env bash
# Shared helpers for the F7-B application bootstrap scripts.
#
# Sourced by utils/bootstrap/<app>.sh and utils/bootstrap-apps.sh — never run directly.
#
# Contract every bootstrap script follows:
#   - idempotent: converge the app, exit 0 when it is already configured
#   - secrets come from the environment or <secrets-dir>/<env>/<NAME>, never from argv
#   - a secret value is never printed, not even on failure
#
# Exit codes: 0 = configured (PASS), 2 = app not deployed (SKIP), 1 = failed (FAIL).
#
# Resolution order:
#   config     $HOMELAB_CONFIG_DIR   -> <repo>/config          -> /opt/homelab/config
#   secrets    $HOMELAB_SECRETS_DIR  -> ~/.homelab-secrets     -> /opt/homelab/secrets
#   compose    $HOMELAB_COMPOSE_DIR  -> <repo>/compose         -> /opt/homelab/compose

set -euo pipefail

HL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HL_REPO_ROOT="$(cd "${HL_LIB_DIR}/../.." && pwd)"

HL_EXIT_SKIP=2

HL_APP="${HL_APP:-bootstrap}"
HOMELAB_ENV="${HOMELAB_ENV:-dev}"
HOMELAB_HOST="${HOMELAB_HOST:-127.0.0.1}"

# --- logging -----------------------------------------------------------------

hl_log() { printf '[%s] %s\n' "$HL_APP" "$*"; }
hl_warn() { printf '[%s] WARN %s\n' "$HL_APP" "$*" >&2; }
hl_die() {
  printf '[%s] FAIL %s\n' "$HL_APP" "$*" >&2
  exit 1
}
hl_skip() {
  printf '[%s] SKIP %s\n' "$HL_APP" "$*"
  exit "$HL_EXIT_SKIP"
}

hl_usage() {
  sed -n "${HL_USAGE_LINES:-2,12}p" "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

hl_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env) HOMELAB_ENV="$2"; shift 2 ;;
      --host) HOMELAB_HOST="$2"; shift 2 ;;
      -h|--help) hl_usage 0 ;;
      *) echo "Unknown option: $1" >&2; hl_usage 1 ;;
    esac
  done
  [[ "$HOMELAB_ENV" == "dev" || "$HOMELAB_ENV" == "prod" ]] ||
    hl_die "--env must be dev or prod"
}

# --- paths -------------------------------------------------------------------

hl_config_dir() {
  if [[ -n "${HOMELAB_CONFIG_DIR:-}" ]]; then
    printf '%s' "$HOMELAB_CONFIG_DIR"
    return 0
  fi
  local candidate
  for candidate in "${HL_REPO_ROOT}/config" /opt/homelab/config; do
    if [[ -f "${candidate}/services.yml" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  hl_die "config/services.yml not found (set HOMELAB_CONFIG_DIR)"
}

hl_compose_dir() {
  if [[ -n "${HOMELAB_COMPOSE_DIR:-}" ]]; then
    printf '%s' "$HOMELAB_COMPOSE_DIR"
    return 0
  fi
  local candidate
  for candidate in /opt/homelab/compose "${HL_REPO_ROOT}/compose"; do
    if [[ -d "${candidate}/core" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  hl_die "compose directory not found (set HOMELAB_COMPOSE_DIR)"
}

hl_secrets_dir() {
  if [[ -n "${HOMELAB_SECRETS_DIR:-}" ]]; then
    printf '%s' "$HOMELAB_SECRETS_DIR"
    return 0
  fi
  local candidate
  for candidate in "${HOME:-/root}/.homelab-secrets" /opt/homelab/secrets; do
    if [[ -d "${candidate}/${HOMELAB_ENV}" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  printf '%s' "${HOME:-/root}/.homelab-secrets"
}

# --- secrets -----------------------------------------------------------------

# hl_secret NAME — value from the environment, else from the per-env secret cache.
hl_secret() {
  local name="$1"
  if [[ -n "${!name:-}" ]]; then
    printf '%s' "${!name}"
    return 0
  fi
  local file
  file="$(hl_secrets_dir)/${HOMELAB_ENV}/${name}"
  [[ -f "$file" ]] || hl_die "secret ${name} not available (env var or ${file})"
  tr -d '\r\n' < "$file"
}

hl_has_secret() {
  local name="$1"
  [[ -n "${!name:-}" ]] && return 0
  [[ -f "$(hl_secrets_dir)/${HOMELAB_ENV}/${name}" ]]
}

# hl_store_secret NAME VALUE — cache a value issued by an app (e.g. the Beszel key).
hl_store_secret() {
  local name="$1" value="$2" dir
  dir="$(hl_secrets_dir)/${HOMELAB_ENV}"
  (umask 077; mkdir -p "$dir"; printf '%s' "$value" > "${dir}/${name}")
  chmod 600 "${dir}/${name}"
}

# --- declarative config ------------------------------------------------------

# hl_account APP FIELD — FIELD is email | username | secret | login | identity.
# `email: environment` resolves to the mailbox of the target environment, the
# same rule utils/gen-app-credentials.sh applies.
hl_account() {
  python3 - "$(hl_config_dir)/identities.yml" "$1" "$2" "$HOMELAB_ENV" <<'PY'
import sys, yaml

path, app, field, environment = sys.argv[1:5]
doc = yaml.safe_load(open(path))
account = next((a for a in doc.get("accounts", []) if a.get("app") == app), None)
if account is None:
    sys.exit(f"no account declared for {app}")
identity = doc.get("identities", {}).get(account.get("identity"), {})


def email_for(ident):
    value = ident.get("email", "")
    if value == "environment":
        return doc.get("environment_email", {}).get(environment, "")
    return value


value = {
    "email": email_for(identity),
    "username": identity.get("username"),
    "secret": account.get("secret"),
    "login": account.get("login"),
    "identity": account.get("identity"),
}.get(field)
if not value:
    sys.exit(f"no {field} declared for {app}")
print(value)
PY
}

# hl_service NAME FIELD — FIELD is any scalar key of the service entry.
hl_service() {
  python3 - "$(hl_config_dir)/services.yml" "$1" "$2" <<'PY'
import sys, yaml

path, name, field = sys.argv[1:4]
doc = yaml.safe_load(open(path))
service = next((s for s in doc.get("services", []) if s.get("name") == name), None)
if service is None:
    sys.exit(f"no service {name} in services.yml")
value = service.get(field)
if value is None:
    sys.exit(f"service {name} has no {field}")
print(value)
PY
}

hl_env_host() {
  python3 - "$(hl_config_dir)/services.yml" "$HOMELAB_ENV" <<'PY'
import sys, yaml

path, env = sys.argv[1:3]
doc = yaml.safe_load(open(path))
print(doc["environments"][env]["host"])
PY
}

# --- docker ------------------------------------------------------------------

hl_container_running() {
  [[ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null || echo false)" == "true" ]]
}

hl_require_container() {
  hl_container_running "$1" || hl_skip "container $1 is not running"
}

# hl_volume_of CONTAINER MOUNTPOINT — the named volume backing a mount point.
hl_volume_of() {
  docker inspect -f "{{range .Mounts}}{{if eq .Destination \"$2\"}}{{.Name}}{{end}}{{end}}" "$1"
}

# --- http --------------------------------------------------------------------

hl_curl() {
  curl -sS --max-time "${HL_HTTP_TIMEOUT:-20}" "$@"
}

hl_http_code() {
  curl -s -k -o /dev/null -w '%{http_code}' --max-time "${HL_HTTP_TIMEOUT:-20}" "$@"
}

# hl_wait_http URL CODES TIMEOUT — CODES is a space separated list.
hl_wait_http() {
  local url="$1" codes="$2" timeout="${3:-90}" waited=0 code
  while (( waited < timeout )); do
    code="$(hl_http_code "$url" || true)"
    if [[ " ${codes} " == *" ${code} "* ]]; then
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  return 1
}

# hl_json_escape VALUE — quote a value for a JSON body. Passed through the
# environment so a secret never shows up in the process list.
hl_json_escape() {
  HL_JSON_INPUT="$1" python3 -c 'import json, os; print(json.dumps(os.environ["HL_JSON_INPUT"]))'
}
