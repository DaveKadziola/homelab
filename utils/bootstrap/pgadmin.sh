#!/usr/bin/env bash
# Configure pgAdmin headlessly (F7-B).
#
#   1. make sure the declared admin exists with the password from the cache —
#      PGADMIN_DEFAULT_* only applies the first time the config database is built
#   2. (re)load compose/core/pgadmin/servers.json so the Postgres connections
#      are predefined instead of added by hand
#
# Usage:
#   ./utils/bootstrap/pgadmin.sh --env dev [--host 127.0.0.1]
#
# Exit: 0 configured, 2 container absent, 1 failed.

HL_APP=pgadmin
HL_USAGE_LINES='2,12'
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hl_parse_args "$@"

CONTAINER="$(hl_service pgadmin container)"
PORT="$(hl_service pgadmin port)"
BASE="http://${HOMELAB_HOST}:${PORT}"
EMAIL="$(hl_account pgadmin email)"
PASSWORD="$(hl_secret "$(hl_account pgadmin secret)")"
SETUP='/venv/bin/python3 /pgadmin4/setup.py'
SERVERS_FILE=/pgadmin4/servers.json

hl_require_container "$CONTAINER"
hl_wait_http "${BASE}/" "200 302" 120 || hl_die "pgAdmin not answering on ${BASE}"

user_exists() {
  docker exec "$CONTAINER" sh -c "${SETUP} get-users --json 2>/dev/null" </dev/null |
    grep -Fq "$EMAIL"
}

login_works() {
  local jar token code ok=1
  jar="$(mktemp)"
  token="$(hl_curl -c "$jar" "${BASE}/login" |
    sed -n 's/.*name="csrf_token"[^>]*value="\([^"]*\)".*/\1/p' | head -n1)"
  if [[ -n "$token" ]]; then
    code="$(HL_PW="$PASSWORD" HL_EMAIL="$EMAIL" HL_TOKEN="$token" python3 -c '
import os, urllib.parse
print(urllib.parse.urlencode({
    "csrf_token": os.environ["HL_TOKEN"],
    "email": os.environ["HL_EMAIL"],
    "password": os.environ["HL_PW"],
}))' |
      curl -s -o /dev/null -w '%{http_code}' --max-time 30 -b "$jar" -c "$jar" \
        -X POST "${BASE}/login" -H "Referer: ${BASE}/login" \
        -H 'Content-Type: application/x-www-form-urlencoded' --data @-)"
    [[ "$code" == "302" ]] && ok=0
  fi
  rm -f "$jar"
  return $ok
}

# Values are expanded inside the container so they never reach this host's argv.
if user_exists; then
  hl_log "updating the password of ${EMAIL}"
  docker exec -e HL_PW="$PASSWORD" "$CONTAINER" \
    sh -c "${SETUP} update-user '${EMAIL}' --password \"\$HL_PW\" --admin" </dev/null >/dev/null 2>&1 ||
    hl_die "setup.py update-user failed"
else
  hl_log "creating the admin ${EMAIL}"
  docker exec -e HL_PW="$PASSWORD" "$CONTAINER" \
    sh -c "${SETUP} add-user '${EMAIL}' \"\$HL_PW\" --admin" </dev/null >/dev/null 2>&1 ||
    hl_die "setup.py add-user failed"
fi

if docker exec "$CONTAINER" test -f "$SERVERS_FILE"; then
  hl_log "loading ${SERVERS_FILE}"
  docker exec "$CONTAINER" \
    sh -c "${SETUP} load-servers ${SERVERS_FILE} --user '${EMAIL}' --replace" </dev/null >/dev/null 2>&1 ||
    hl_warn "setup.py load-servers failed — servers left as they were"
else
  hl_warn "${SERVERS_FILE} is not mounted — redeploy compose/core to add it"
fi

login_works || hl_warn "could not complete an HTTP login check for ${EMAIL}"
hl_log "OK"
