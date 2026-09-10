#!/usr/bin/env bash
# Configure the Syncthing GUI account headlessly (F7-B).
#
#   1. read the API key Syncthing generated in its config.xml
#   2. set the GUI user/password declared in config/identities.yml
#   3. verify session login against /rest/noauth/auth/password
#      (current Syncthing dropped HTTP basic auth for the GUI)
#
# Peers and folders are not touched — device IDs are created on first start and
# pairing stays a deliberate action (docs/kb/apps/syncthing.md).
#
# Usage:
#   ./utils/bootstrap/syncthing.sh --env dev [--host 127.0.0.1]
#
# Exit: 0 configured, 2 container absent, 1 failed.

HL_APP=syncthing
HL_USAGE_LINES='2,14'
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hl_parse_args "$@"

CONTAINER="$(hl_service syncthing container)"
PORT="$(hl_service syncthing port)"
BASE="http://${HOMELAB_HOST}:${PORT}"
USERNAME="$(hl_account syncthing username)"
PASSWORD="$(hl_secret "$(hl_account syncthing secret)")"

hl_require_container "$CONTAINER"
hl_wait_http "${BASE}/rest/noauth/health" "200" 60 || hl_wait_http "${BASE}/" "200" 60 ||
  hl_die "Syncthing not answering on ${BASE}"

api_key() {
  docker exec "$CONTAINER" cat /var/syncthing/config/config.xml 2>/dev/null |
    sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' | head -n1
}

auth_works() {
  local code
  code="$(printf '{"username":%s,"password":%s}' \
    "$(hl_json_escape "$USERNAME")" "$(hl_json_escape "$PASSWORD")" |
    curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
      -X POST "${BASE}/rest/noauth/auth/password" \
      -H 'Content-Type: application/json' --data @-)"
  [[ "$code" == "200" || "$code" == "204" ]]
}

KEY="$(api_key)"
[[ -n "$KEY" ]] || hl_die "cannot read the API key from ${CONTAINER}:/var/syncthing/config/config.xml"

if auth_works; then
  hl_log "GUI account ${USERNAME} already matches the declared credential"
  hl_log "OK"
  exit 0
fi

hl_log "setting the GUI account to ${USERNAME}"
GUI="$(hl_curl -H "X-API-Key: ${KEY}" "${BASE}/rest/config/gui")"
CODE="$(HL_GUI="$GUI" HL_USER="$USERNAME" HL_PW="$PASSWORD" python3 -c '
import json, os

gui = json.loads(os.environ["HL_GUI"])
gui["user"] = os.environ["HL_USER"]
gui["password"] = os.environ["HL_PW"]  # Syncthing hashes it on save
gui["authMode"] = "static"
print(json.dumps(gui))' |
  curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X PUT "${BASE}/rest/config/gui" \
    -H "X-API-Key: ${KEY}" -H 'Content-Type: application/json' --data @-)"
[[ "$CODE" == "200" ]] || hl_die "GUI config rejected (HTTP ${CODE})"

if [[ "$(hl_curl -H "X-API-Key: ${KEY}" "${BASE}/rest/config/restart-required")" == *true* ]]; then
  hl_log "restarting Syncthing to apply the GUI config"
  hl_curl -o /dev/null -X POST -H "X-API-Key: ${KEY}" "${BASE}/rest/system/restart"
  sleep 5
fi

for _ in 1 2 3 4 5 6 7 8 9 10; do
  auth_works && break
  sleep 3
done
auth_works || hl_die "basic auth still fails for ${USERNAME}"
hl_log "GUI account ${USERNAME} converged"
hl_log "OK"
