#!/usr/bin/env bash
# Configure Portainer headlessly (F7-B).
#
#   1. create the admin declared in config/identities.yml if none exists
#   2. reconcile the admin password when it drifted (helper-reset-password)
#   3. ensure the local Docker endpoint exists
#   4. ensure the grocery stack exists, from compose/grocery/docker-compose.yml
#
# Usage:
#   ./utils/bootstrap/portainer.sh --env dev [--host 127.0.0.1]
#
# Exit: 0 configured, 2 container absent, 1 failed.

HL_APP=portainer
HL_USAGE_LINES='2,12'
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hl_parse_args "$@"

CONTAINER="$(hl_service portainer container)"
PORT="$(hl_service portainer port)"
BASE="http://${HOMELAB_HOST}:${PORT}"
USERNAME="$(hl_account portainer username)"
PASSWORD="$(hl_secret "$(hl_account portainer secret)")"
GROCERY_STACK="easytodo-grocery"

hl_require_container "$CONTAINER"
hl_wait_http "${BASE}/api/status" "200" 60 || hl_die "Portainer API not answering on ${BASE}"

login() {
  local password="$1" body
  body="{\"Username\":$(hl_json_escape "$USERNAME"),\"Password\":$(hl_json_escape "$password")}"
  printf '%s' "$body" |
    hl_curl -X POST "${BASE}/api/auth" -H 'Content-Type: application/json' --data @- 2>/dev/null |
    python3 -c 'import json,sys; print(json.load(sys.stdin).get("jwt",""))' 2>/dev/null || true
}

admin_exists() {
  [[ "$(hl_http_code "${BASE}/api/users/admin/check")" == "204" ]]
}

# Portainer refuses to create the first admin long after startup; restart it so
# the security timeout window is open again.
create_admin() {
  hl_log "no admin yet — creating ${USERNAME}"
  local body
  body="{\"Username\":$(hl_json_escape "$USERNAME"),\"Password\":$(hl_json_escape "$PASSWORD")}"
  local code
  code="$(printf '%s' "$body" |
    curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
      -X POST "${BASE}/api/users/admin/init" -H 'Content-Type: application/json' --data @-)"
  if [[ "$code" != "200" ]]; then
    hl_log "admin init returned ${code}, restarting Portainer to reopen the init window"
    docker restart "$CONTAINER" >/dev/null
    hl_wait_http "${BASE}/api/status" "200" 60 || hl_die "Portainer did not come back after restart"
    code="$(printf '%s' "$body" |
      curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
        -X POST "${BASE}/api/users/admin/init" -H 'Content-Type: application/json' --data @-)"
  fi
  [[ "$code" == "200" ]] || hl_die "admin init failed (HTTP ${code})"
}

# Portainer has no "set password without knowing it" API. The supported path is
# the official helper image, which writes a temporary password into the volume.
reset_admin_password() {
  local volume temp_password
  volume="$(hl_volume_of "$CONTAINER" /data)"
  [[ -n "$volume" ]] || hl_die "cannot find the /data volume of ${CONTAINER}"
  hl_log "admin password drifted — resetting through portainer/helper-reset-password"
  docker stop "$CONTAINER" >/dev/null
  temp_password="$(docker run --rm -v "${volume}:/data" portainer/helper-reset-password 2>&1 |
    tr -d '\r' | sed -n -E 's/.*[Pp]assword[: ]+//p' | tail -n1 | awk '{print $1}')"
  docker start "$CONTAINER" >/dev/null
  hl_wait_http "${BASE}/api/status" "200" 90 || hl_die "Portainer did not restart after the password reset"
  [[ -n "$temp_password" ]] || hl_die "helper-reset-password did not report a password"

  local jwt
  jwt="$(login "$temp_password")"
  [[ -n "$jwt" ]] || hl_die "cannot log in with the temporary password"

  local user_id body code
  user_id="$(hl_curl -H "Authorization: Bearer ${jwt}" "${BASE}/api/users" |
    python3 -c 'import json,sys; print(next(u["Id"] for u in json.load(sys.stdin) if u["Role"]==1))')"
  body="{\"password\":$(hl_json_escape "$temp_password"),\"newPassword\":$(hl_json_escape "$PASSWORD")}"
  code="$(printf '%s' "$body" |
    curl -s -o /dev/null -w '%{http_code}' --max-time 20 -X PUT \
      "${BASE}/api/users/${user_id}/passwd" \
      -H "Authorization: Bearer ${jwt}" -H 'Content-Type: application/json' --data @-)"
  [[ "$code" == "204" || "$code" == "200" ]] || hl_die "password change rejected (HTTP ${code})"
  unset temp_password
}

ensure_local_endpoint() {
  local jwt="$1" endpoints
  endpoints="$(hl_curl -H "Authorization: Bearer ${jwt}" "${BASE}/api/endpoints" |
    python3 -c 'import json,sys; print(" ".join(e["Name"] for e in json.load(sys.stdin)))')"
  if [[ " ${endpoints} " == *" local "* ]]; then
    hl_log "local Docker endpoint present"
    return 0
  fi
  hl_log "creating the local Docker endpoint"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X POST "${BASE}/api/endpoints" \
    -H "Authorization: Bearer ${jwt}" \
    -F 'Name=local' -F 'EndpointCreationType=1')"
  [[ "$code" == "200" ]] || hl_die "endpoint creation failed (HTTP ${code})"
}

ensure_grocery_stack() {
  local jwt="$1" stacks compose_file endpoint_id code
  stacks="$(hl_curl -H "Authorization: Bearer ${jwt}" "${BASE}/api/stacks" |
    python3 -c 'import json,sys; print(" ".join(s["Name"] for s in json.load(sys.stdin)))')"
  if [[ " ${stacks} " == *" ${GROCERY_STACK} "* ]]; then
    hl_log "stack ${GROCERY_STACK} present"
    return 0
  fi
  compose_file="$(hl_compose_dir)/grocery/docker-compose.yml"
  if [[ ! -f "$compose_file" ]]; then
    hl_warn "stack ${GROCERY_STACK} missing and ${compose_file} not on this host — skipping"
    return 0
  fi
  if ! hl_has_secret GROCERY_DB_PASSWORD; then
    hl_warn "stack ${GROCERY_STACK} missing and GROCERY_DB_PASSWORD unavailable — skipping"
    return 0
  fi
  hl_log "creating stack ${GROCERY_STACK}"
  endpoint_id="$(hl_curl -H "Authorization: Bearer ${jwt}" "${BASE}/api/endpoints" |
    python3 -c 'import json,sys; print(next(e["Id"] for e in json.load(sys.stdin) if e["Name"]=="local"))')"
  code="$(
    HL_COMPOSE_FILE="$compose_file" \
    HL_STACK_NAME="$GROCERY_STACK" \
    HL_DB_PASSWORD="$(hl_secret GROCERY_DB_PASSWORD)" \
    HL_APP_HOST="$(hl_env_host)" \
    python3 <<'PY' | curl -s -o /dev/null -w '%{http_code}' --max-time 60 -X POST \
        "${BASE}/api/stacks/create/standalone/string?endpointId=${endpoint_id}" \
        -H "Authorization: Bearer ${jwt}" -H 'Content-Type: application/json' --data @-
import json, os

env = {
    "DB_HOST": "host.docker.internal",
    "DB_PORT": "5432",
    "DB_NAME": "todo_grocery",
    "DB_USER": "prod_todo_grocery",
    "DB_PASSWORD": os.environ["HL_DB_PASSWORD"],
    "DB_SCHEMA": "prod",
    "APP_HOST_NAME": "0.0.0.0",
    "APP_HOST_PORT": "8101",
    "SOCKETIO_HOST": os.environ["HL_APP_HOST"],
    "SOCKETIO_PORT": "8101",
}
print(json.dumps({
    "name": os.environ["HL_STACK_NAME"],
    "stackFileContent": open(os.environ["HL_COMPOSE_FILE"]).read(),
    "env": [{"name": k, "value": v} for k, v in env.items()],
}))
PY
  )"
  [[ "$code" == "200" ]] || hl_die "stack creation failed (HTTP ${code})"
}

JWT="$(login "$PASSWORD")"
if [[ -z "$JWT" ]]; then
  if admin_exists; then
    reset_admin_password
  else
    create_admin
  fi
  JWT="$(login "$PASSWORD")"
  [[ -n "$JWT" ]] || hl_die "cannot authenticate as ${USERNAME} after configuring the admin"
  hl_log "admin ${USERNAME} converged"
else
  hl_log "admin ${USERNAME} already matches the declared credential"
fi

ensure_local_endpoint "$JWT"
ensure_grocery_stack "$JWT"
hl_log "OK"
