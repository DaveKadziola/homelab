#!/usr/bin/env bash
# Configure the Beszel hub and its local agent headlessly (F7-B, F10-A).
#
#   1. create or update the hub superuser declared in config/identities.yml
#   2. beszel_config.py: the Beszel user with the same login, the system <env>-apps and its agent
#      token, compose/core/beszel-agent.env (KEY + TOKEN) and a running beszel-agent, the alerts
#      of config/monitoring.yml, the alert mail address and the hub SMTP relay
#
# Usage:
#   ./utils/bootstrap/beszel.sh --env dev [--host 127.0.0.1]
#
# Exit: 0 configured, 2 container absent, 1 failed.

HL_APP=beszel
HL_USAGE_LINES='2,12'
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
# The agent dials the hub; host:port is only the hub's fallback to reach the agent.
ENV_HOST="$(hl_env_host)"

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

TOKEN="$(auth_token)"
if [[ -n "$TOKEN" ]]; then
  hl_log "superuser ${EMAIL} already matches the declared credential"
else
  upsert_superuser
  TOKEN="$(auth_token)"
  [[ -n "$TOKEN" ]] || hl_die "cannot authenticate as ${EMAIL} after the upsert"
  hl_log "superuser ${EMAIL} converged"
fi

# Optional: without a relay login (prod before the owner makes it) the SMTP step only warns.
for name in SMTP_USERNAME SMTP_PASSWORD; do
  if hl_has_secret "$name"; then export "${name}=$(hl_secret "$name")"; fi
done

BESZEL_EMAIL="$EMAIL" BESZEL_PASSWORD="$PASSWORD" python3 "${HL_LIB_DIR}/beszel_config.py" \
  --base "$BASE" --config "$(hl_config_dir)" --compose-dir "$(hl_compose_dir)" --env "$HOMELAB_ENV" \
  --system "$SYSTEM_NAME" --host "$ENV_HOST" --port "$AGENT_PORT" \
  --username "$(hl_account beszel username)" --app-url "http://${ENV_HOST}:${PORT}" ||
  hl_die "hub configuration failed"
hl_log "OK"
