#!/usr/bin/env bash
# Configure the Beszel hub headlessly (F7-B).
#
#   1. create or update the hub superuser declared in config/identities.yml
#   2. register this Docker host as a monitored system if it is missing
#   3. store the agent key issued by the hub as BESZEL_KEY in the secret cache,
#      so the next deploy can start the beszel-agent compose profile
#
# Usage:
#   ./utils/bootstrap/beszel.sh --env dev [--host 127.0.0.1]
#
# Exit: 0 configured, 2 container absent, 1 failed.

HL_APP=beszel
HL_USAGE_LINES='2,13'
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hl_parse_args "$@"

CONTAINER="$(hl_service beszel container)"
PORT="$(hl_service beszel port)"
AGENT_PORT="$(hl_service beszel-agent port)"
BASE="http://${HOMELAB_HOST}:${PORT}"
EMAIL="$(hl_account beszel email)"
PASSWORD="$(hl_secret "$(hl_account beszel secret)")"
SYSTEM_NAME="${HOMELAB_ENV}-apps"

hl_require_container "$CONTAINER"
hl_wait_http "${BASE}/api/health" "200" 90 || hl_die "Beszel hub not answering on ${BASE}"

auth_token() {
  local body
  body="{\"identity\":$(hl_json_escape "$EMAIL"),\"password\":$(hl_json_escape "$PASSWORD")}"
  printf '%s' "$body" |
    hl_curl -X POST "${BASE}/api/collections/_superusers/auth-with-password" \
      -H 'Content-Type: application/json' --data @- 2>/dev/null |
    python3 -c 'import json,sys; print(json.load(sys.stdin).get("token",""))' 2>/dev/null || true
}

# The hub image is distroless: no shell, so the value goes on the container
# command line. It stays inside the container's own argv.
upsert_superuser() {
  hl_log "upserting the hub superuser ${EMAIL}"
  docker exec "$CONTAINER" /beszel superuser upsert "$EMAIL" "$PASSWORD" --dir /beszel_data >/dev/null 2>&1 ||
    hl_die "beszel superuser upsert failed"
}

# The agent authenticates with the hub's public key — not a secret, but it is
# cached next to the secrets so deploy can inject it like any other value.
store_agent_key() {
  local key
  key="$(hl_curl "${BASE}/api/beszel/getkey" |
    python3 -c 'import json,sys; print(json.load(sys.stdin).get("key",""))' 2>/dev/null || true)"
  if [[ -z "$key" ]]; then
    hl_warn "the hub did not return an agent key — beszel-agent stays disabled"
    return 0
  fi
  if [[ "$(hl_has_secret BESZEL_KEY && hl_secret BESZEL_KEY || echo)" == "$key" ]]; then
    hl_log "agent key already cached"
    return 0
  fi
  hl_store_secret BESZEL_KEY "$key"
  hl_log "cached the agent key as BESZEL_KEY (redeploy with COMPOSE_PROFILES=…,beszel-agent)"
}

ensure_system() {
  local token="$1" existing code docker_host_ip
  existing="$(hl_curl -H "Authorization: ${token}" \
    "${BASE}/api/collections/systems/records?perPage=200" |
    python3 -c 'import json,sys; print("|".join(r["name"] for r in json.load(sys.stdin).get("items",[])))')"
  if [[ "|${existing}|" == *"|${SYSTEM_NAME}|"* ]]; then
    hl_log "system ${SYSTEM_NAME} already registered"
    return 0
  fi
  # The agent runs with network_mode: host, so the hub reaches it on the bridge gateway.
  docker_host_ip="$(docker network inspect bridge -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null || true)"
  docker_host_ip="${docker_host_ip:-172.17.0.1}"
  hl_log "registering system ${SYSTEM_NAME} at ${docker_host_ip}:${AGENT_PORT}"
  code="$(printf '{"name":"%s","host":"%s","port":"%s","status":"pending"}' \
    "$SYSTEM_NAME" "$docker_host_ip" "$AGENT_PORT" |
    curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X POST \
      "${BASE}/api/collections/systems/records" \
      -H "Authorization: ${token}" -H 'Content-Type: application/json' --data @-)"
  [[ "$code" == "200" ]] || hl_warn "system registration returned HTTP ${code} — add it from the hub UI if it stays missing"
}

TOKEN="$(auth_token)"
if [[ -n "$TOKEN" ]]; then
  hl_log "superuser ${EMAIL} already matches the declared credential"
else
  upsert_superuser
  TOKEN="$(auth_token)"
  [[ -n "$TOKEN" ]] || hl_die "cannot authenticate as ${EMAIL} after the upsert"
  hl_log "superuser ${EMAIL} converged"
fi

ensure_system "$TOKEN"
store_agent_key
hl_log "OK"
