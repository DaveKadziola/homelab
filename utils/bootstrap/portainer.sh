#!/usr/bin/env bash
# Configure Portainer headlessly (F7-B).
#
#   1. create the admin declared in config/identities.yml if none exists
#   2. reconcile the admin password when it drifted (helper-reset-password)
#   3. ensure the local Docker endpoint exists
#   4. ensure the grocery stack exists and matches compose/grocery/docker-compose.yml + its env,
#      then the grocery admin declared in config/identities.yml
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

# Newer Portainer CE prints a one-time setup token at startup and refuses the
# first admin (HTTP 403) without it in the X-Setup-Token header. Read the token
# of the current start from the container log; never print it.
setup_token() {
  local started
  started="$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER" 2>/dev/null)"
  docker logs --since "$started" "$CONTAINER" 2>&1 |
    sed -n -E 's/^setup_token=([0-9a-fA-F]+).*/\1/p' | tail -n1
}

init_admin() {
  local body="$1" token
  local -a headers=(-H 'Content-Type: application/json')
  token="$(setup_token)"
  [[ -n "$token" ]] && headers+=(-H "X-Setup-Token: ${token}")
  printf '%s' "$body" |
    curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
      -X POST "${BASE}/api/users/admin/init" "${headers[@]}" --data @-
}

# Portainer refuses to create the first admin long after startup; restart it so
# the security timeout window is open again.
create_admin() {
  hl_log "no admin yet — creating ${USERNAME}"
  local body code
  body="{\"Username\":$(hl_json_escape "$USERNAME"),\"Password\":$(hl_json_escape "$PASSWORD")}"
  code="$(init_admin "$body")"
  if [[ "$code" != "200" ]]; then
    hl_log "admin init returned ${code}, restarting Portainer to reopen the init window"
    docker restart "$CONTAINER" >/dev/null
    hl_wait_http "${BASE}/api/status" "200" 60 || hl_die "Portainer did not come back after restart"
    code="$(init_admin "$body")"
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

# grocery_env <jwt>: the declared stack env as JSON (secret values only on stdout, into the API call).
# The image comes from deploy-core.yml (GROCERY_IMAGE); a manual run keeps the stack's current one.
grocery_env() {
  local jwt="$1" public_url
  if [[ "$HOMELAB_ENV" == "prod" ]]; then
    public_url="$(hl_service grocery public_url)"
  else
    public_url="http://$(hl_env_host):$(hl_service grocery port)"
  fi
  HL_JWT="$jwt" HL_BASE="$BASE" HL_NAME="$GROCERY_STACK" HL_PUBLIC_URL="$public_url" \
  HL_PUBLIC_PROXY="$(hl_env_field public_proxy)" \
  HL_DB_PASSWORD="$(hl_secret GROCERY_DB_PASSWORD)" \
  HL_SECRET_KEY="$(hl_secret GROCERY_SECRET_KEY)" \
  HL_SMTP_PASSWORD="$(hl_has_secret GROCERY_PROTON_SMTP_TOKEN && hl_secret GROCERY_PROTON_SMTP_TOKEN)" \
  python3 <<'PY'
import json, os, sys, urllib.request

req = urllib.request.Request(os.environ["HL_BASE"] + "/api/stacks",
                             headers={"Authorization": "Bearer " + os.environ["HL_JWT"]})
stacks = json.load(urllib.request.urlopen(req, timeout=60))
stack = next((s for s in stacks if s["Name"] == os.environ["HL_NAME"]), None)
current = {e["name"]: e["value"] for e in (stack or {}).get("Env") or []}
image = os.environ.get("GROCERY_IMAGE") or current.get("GROCERY_IMAGE", "")
if not image:
    sys.exit("GROCERY_IMAGE unset and the stack has none: run deploy-core.yml")
smtp = os.environ["HL_SMTP_PASSWORD"]
env = {
    "GROCERY_IMAGE": image,
    "DB_PASSWORD": os.environ["HL_DB_PASSWORD"],
    "SECRET_KEY": os.environ["HL_SECRET_KEY"],
    "PUBLIC_URL": os.environ["HL_PUBLIC_URL"],
    "FORWARDED_ALLOW_IPS": os.environ["HL_PUBLIC_PROXY"] or "127.0.0.1",
    "MAIL_BACKEND": "smtp" if smtp else "console",
    "SMTP_PASSWORD": smtp,
}
print(json.dumps([{"name": k, "value": v} for k, v in env.items()]))
PY
}

# redeploy_stack <jwt> <name> <compose file> <env json> <running 0|1>: replace the stored file and
# env; exit 3 = both unchanged and running, nothing done.
redeploy_stack() {
  local jwt="$1" name="$2"
  HL_JWT="$jwt" HL_NAME="$name" HL_BASE="$BASE" HL_FILE="$3" HL_RUNNING="$5" python3 3<<<"$4" <<'PY'
import json, os, sys, urllib.request

base, jwt, name = os.environ["HL_BASE"], os.environ["HL_JWT"], os.environ["HL_NAME"]


def call(method, path, body=None):
    req = urllib.request.Request(base + "/api" + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": "Bearer " + jwt, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as r:
        raw = r.read()
        return json.loads(raw) if raw else None


env = json.load(os.fdopen(3))
stack = next((s for s in call("GET", "/stacks") if s["Name"] == name), None)
if not stack:
    sys.exit(1)
content = call("GET", f"/stacks/{stack['Id']}/file")["StackFileContent"]
new = open(os.environ["HL_FILE"]).read()
key = lambda e: sorted((x["name"], x["value"]) for x in e)
if new == content and key(env) == key(stack.get("Env") or []) and os.environ["HL_RUNNING"] == "1":
    sys.exit(3)
call("PUT", f"/stacks/{stack['Id']}?endpointId={stack['EndpointId']}",
     {"stackFileContent": new, "env": env, "prune": True, "pullImage": False})
PY
}

ensure_grocery_stack() {
  local jwt="$1" stacks compose_file endpoint_id code env
  compose_file="$(hl_compose_dir)/grocery/docker-compose.yml"
  if [[ ! -f "$compose_file" ]]; then
    hl_warn "${compose_file} not on this host — skipping stack ${GROCERY_STACK}"
    return 0
  fi
  if ! hl_has_secret GROCERY_DB_PASSWORD || ! hl_has_secret GROCERY_SECRET_KEY; then
    hl_warn "GROCERY_DB_PASSWORD or GROCERY_SECRET_KEY unavailable — skipping stack ${GROCERY_STACK}"
    return 0
  fi
  env="$(grocery_env "$jwt")" || hl_die "cannot build the env of ${GROCERY_STACK}"
  stacks="$(hl_curl -H "Authorization: Bearer ${jwt}" "${BASE}/api/stacks" |
    python3 -c 'import json,sys; print(" ".join(s["Name"] for s in json.load(sys.stdin)))')"
  if [[ " ${stacks} " == *" ${GROCERY_STACK} "* ]]; then
    local running=0 rc=0
    docker ps --format '{{.Names}}' | grep -q "^${GROCERY_STACK}-" && running=1
    # Portainer keeps the file and env the stack was created with, so changes reach the container
    # only through an update. A stopped stack is redeployed too: "start" would try to pull the
    # local-only image.
    redeploy_stack "$jwt" "$GROCERY_STACK" "$compose_file" "$env" "$running" || rc=$?
    case $rc in
      0) hl_log "stack ${GROCERY_STACK} redeployed without pull (compose file or env changed, or not running)" ;;
      3) hl_log "stack ${GROCERY_STACK} present, running and matching ${compose_file##*/compose/}" ;;
      *) hl_die "redeploy of ${GROCERY_STACK} failed" ;;
    esac
  else
    hl_log "creating stack ${GROCERY_STACK}"
    endpoint_id="$(hl_curl -H "Authorization: Bearer ${jwt}" "${BASE}/api/endpoints" |
      python3 -c 'import json,sys; print(next(e["Id"] for e in json.load(sys.stdin) if e["Name"]=="local"))')"
    code="$(
      HL_COMPOSE_FILE="$compose_file" HL_STACK_NAME="$GROCERY_STACK" python3 3<<<"$env" -c '
import json, os
print(json.dumps({"name": os.environ["HL_STACK_NAME"],
                  "stackFileContent": open(os.environ["HL_COMPOSE_FILE"]).read(),
                  "env": json.load(os.fdopen(3))}))' |
        curl -s -o /dev/null -w '%{http_code}' --max-time 600 -X POST \
          "${BASE}/api/stacks/create/standalone/string?endpointId=${endpoint_id}" \
          -H "Authorization: Bearer ${jwt}" -H 'Content-Type: application/json' --data @-
    )"
    [[ "$code" == "200" ]] || hl_die "stack creation failed (HTTP ${code})"
  fi
  ensure_grocery_admin
}

# create-admin creates the account, or makes an existing one admin without touching its password.
ensure_grocery_admin() {
  local container="${GROCERY_STACK}-easytodo-1" email out attempt
  hl_has_secret GROCERY_ADMIN_PASSWORD || { hl_warn "GROCERY_ADMIN_PASSWORD unavailable — grocery admin not ensured"; return 0; }
  email="$(hl_account grocery email)"
  # The stack update can return while the old container still answers and is about to be replaced
  # (deploy 2026-10-21): wait for the declared image, then for health; retry the exec once or twice.
  for attempt in 1 2 3; do
    if [[ -n "${GROCERY_IMAGE:-}" ]]; then
      local waited=0
      until [[ "$(docker inspect -f '{{.Config.Image}} {{.State.Running}}' "$container" 2>/dev/null)" == "${GROCERY_IMAGE} true" ]]; do
        (( waited >= 180 )) && hl_die "${container} is not running ${GROCERY_IMAGE} after 180 s"
        sleep 5; waited=$((waited + 5))
      done
    fi
    hl_wait_http "http://${HOMELAB_HOST}:$(hl_service grocery port)/healthz" "200" 120 ||
      hl_die "grocery not healthy after deploy"
    if out="$(hl_secret GROCERY_ADMIN_PASSWORD |
      docker exec -i "$container" python -m easytodo.cli create-admin --email "$email" --password-stdin 2>&1)"; then
      hl_log "grocery admin ${email} ensured"
      return 0
    fi
    hl_warn "grocery create-admin attempt ${attempt} failed: $(tail -n1 <<<"$out")"
    sleep 10
  done
  hl_die "grocery create-admin failed"
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
