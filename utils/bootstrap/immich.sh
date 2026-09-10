#!/usr/bin/env bash
# Configure Immich headlessly (F7-B).
#
#   1. reconcile the admin account to the identity declared in config/identities.yml
#      (the DEV instance was created by hand as admin@admin.com — it gets renamed)
#   2. set the admin password from the secret cache, clearing "must change password"
#   3. apply compose/core/immich/system-config.json on top of the running config
#
# Usage:
#   ./utils/bootstrap/immich.sh --env dev [--host 127.0.0.1]
#
# Exit: 0 configured, 2 container absent, 1 failed.

HL_APP=immich
HL_USAGE_LINES='2,12'
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hl_parse_args "$@"

CONTAINER="$(hl_service immich container)"
PORT="$(hl_service immich port)"
BASE="http://${HOMELAB_HOST}:${PORT}/api"
EMAIL="$(hl_account immich email)"
NAME="$(hl_account immich identity)"
PASSWORD="$(hl_secret "$(hl_account immich secret)")"
SYSTEM_CONFIG="$(hl_compose_dir)/core/immich/system-config.json"

hl_require_container "$CONTAINER"
hl_wait_http "${BASE}/server/ping" "200" 120 || hl_die "Immich API not answering on ${BASE}"

login() {
  local email="$1" body
  body="{\"email\":$(hl_json_escape "$email"),\"password\":$(hl_json_escape "$PASSWORD")}"
  printf '%s' "$body" |
    hl_curl -X POST "${BASE}/auth/login" -H 'Content-Type: application/json' --data @- 2>/dev/null |
    python3 -c 'import json,sys; print(json.load(sys.stdin).get("accessToken",""))' 2>/dev/null || true
}

current_admin_email() {
  docker exec "$CONTAINER" immich-admin list-users 2>/dev/null | python3 -c '
import re, sys

text = sys.stdin.read()
for block in text.split("{")[1:]:
    email = re.search(r"email: \x27([^\x27]+)\x27", block)
    admin = re.search(r"isAdmin: (true|false)", block)
    if email and admin and admin.group(1) == "true":
        print(email.group(1))
        break
'
}

# The CLI is an interactive inquirer prompt and ignores a plain pipe (no TTY).
# pexpect drives it; stdout is discarded because it echoes the password.
reset_password() {
  hl_log "resetting the admin password through immich-admin"
  HL_CONTAINER="$CONTAINER" HL_PW="$PASSWORD" python3 - <<'PY' >/dev/null
import os, sys
try:
    import pexpect
except ImportError:
    sys.exit(2)
child = pexpect.spawn(
    "docker",
    ["exec", "-i", os.environ["HL_CONTAINER"], "immich-admin", "reset-admin-password"],
    encoding="utf-8",
    timeout=60,
)
child.expect("password")
child.sendline(os.environ["HL_PW"])
child.expect("Invalidate")
child.sendline("y")
child.expect(pexpect.EOF)
sys.exit(0 if child.wait() == 0 else 1)
PY
  local rc=$?
  [[ $rc -eq 2 ]] && hl_die "python3-pexpect is required on the app host for Immich password reset"
  [[ $rc -eq 0 ]] || hl_die "immich-admin reset-admin-password failed"
}

update_me() {
  local token="$1" body="$2" code
  code="$(printf '%s' "$body" |
    curl -s -o /dev/null -w '%{http_code}' --max-time 20 -X PUT "${BASE}/users/me" \
      -H "Authorization: Bearer ${token}" -H 'Content-Type: application/json' --data @-)"
  printf '%s' "$code"
}

apply_system_config() {
  local token="$1" current merged code
  [[ -f "$SYSTEM_CONFIG" ]] || return 0
  current="$(hl_curl -H "Authorization: Bearer ${token}" "${BASE}/system-config")"
  merged="$(HL_CURRENT="$current" python3 - "$SYSTEM_CONFIG" <<'PY'
import json, os, sys

current = json.loads(os.environ["HL_CURRENT"])
desired = json.load(open(sys.argv[1]))
changed = []


def merge(base, overlay, path=""):
    for key, value in overlay.items():
        where = f"{path}.{key}" if path else key
        if key not in base:
            print(f"unknown key {where}", file=sys.stderr)
            continue
        if isinstance(value, dict) and isinstance(base[key], dict):
            merge(base[key], value, where)
        elif base[key] != value:
            base[key] = value
            changed.append(where)


merge(current, desired)
print(json.dumps({"config": current, "changed": changed}))
PY
  )"
  local changed
  changed="$(printf '%s' "$merged" | python3 -c 'import json,sys; print(" ".join(json.load(sys.stdin)["changed"]))')"
  if [[ -z "$changed" ]]; then
    hl_log "system config already matches system-config.json"
    return 0
  fi
  hl_log "applying system config: ${changed}"
  code="$(printf '%s' "$merged" |
    python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["config"]))' |
    curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X PUT "${BASE}/system-config" \
      -H "Authorization: Bearer ${token}" -H 'Content-Type: application/json' --data @-)"
  [[ "$code" == "200" ]] || hl_warn "system config rejected (HTTP ${code}) — left unchanged"
}

TOKEN="$(login "$EMAIL")"
if [[ -n "$TOKEN" ]]; then
  hl_log "admin ${EMAIL} already matches the declared credential"
else
  CURRENT_EMAIL="$(current_admin_email)"
  [[ -n "$CURRENT_EMAIL" ]] || hl_die "no admin user found in Immich"
  reset_password
  TOKEN="$(login "$CURRENT_EMAIL")"
  [[ -n "$TOKEN" ]] || hl_die "cannot log in after the password reset"

  if [[ "$CURRENT_EMAIL" != "$EMAIL" ]]; then
    hl_log "renaming the admin account ${CURRENT_EMAIL} -> ${EMAIL}"
    code="$(update_me "$TOKEN" "{\"email\":$(hl_json_escape "$EMAIL"),\"name\":$(hl_json_escape "$NAME")}")"
    [[ "$code" == "200" ]] || hl_die "email change rejected (HTTP ${code})"
    TOKEN="$(login "$EMAIL")"
    [[ -n "$TOKEN" ]] || hl_die "cannot log in as ${EMAIL} after the rename"
  fi

  # Re-setting the same password clears Immich's "must change password" flag.
  code="$(update_me "$TOKEN" "{\"password\":$(hl_json_escape "$PASSWORD")}")"
  [[ "$code" == "200" ]] || hl_warn "could not clear shouldChangePassword (HTTP ${code})"
  hl_log "admin ${EMAIL} converged"
fi

apply_system_config "$TOKEN"
hl_log "OK"
