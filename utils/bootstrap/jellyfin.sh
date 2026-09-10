#!/usr/bin/env bash
# Configure Jellyfin headlessly (F7-B).
#
#   1. run the /Startup/* wizard: locale, admin user, remote access, complete
#   2. create the media libraries declared under `libraries:` in config/services.yml
#
# The wizard endpoints only answer while the wizard is pending, so a re-run
# short-circuits to a login check.
#
# Usage:
#   ./utils/bootstrap/jellyfin.sh --env dev [--host 127.0.0.1]
#
# Exit: 0 configured, 2 container absent, 1 failed.

HL_APP=jellyfin
HL_USAGE_LINES='2,14'
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hl_parse_args "$@"

CONTAINER="$(hl_service jellyfin container)"
PORT="$(hl_service jellyfin port)"
BASE="http://${HOMELAB_HOST}:${PORT}"
USERNAME="$(hl_account jellyfin username)"
PASSWORD="$(hl_secret "$(hl_account jellyfin secret)")"
AUTH_HEADER='Authorization: MediaBrowser Client="homelab-bootstrap", Device="ansible", DeviceId="homelab-bootstrap", Version="1.0.0"'

hl_require_container "$CONTAINER"
hl_wait_http "${BASE}/System/Info/Public" "200" 120 || hl_die "Jellyfin not answering on ${BASE}"

wizard_done() {
  hl_curl "${BASE}/System/Info/Public" |
    python3 -c 'import json,sys; print(str(json.load(sys.stdin).get("StartupWizardCompleted", False)).lower())'
}

post_json() {
  local path="$1" body="$2"
  printf '%s' "$body" |
    curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X POST "${BASE}${path}" \
      -H "$AUTH_HEADER" -H 'Content-Type: application/json' --data @-
}

login() {
  local body
  body="{\"Username\":$(hl_json_escape "$USERNAME"),\"Pw\":$(hl_json_escape "$PASSWORD")}"
  printf '%s' "$body" |
    hl_curl -X POST "${BASE}/Users/AuthenticateByName" \
      -H "$AUTH_HEADER" -H 'Content-Type: application/json' --data @- 2>/dev/null |
    python3 -c 'import json,sys; print(json.load(sys.stdin).get("AccessToken",""))' 2>/dev/null || true
}

run_wizard() {
  local code
  hl_log "running the startup wizard"
  code="$(post_json /Startup/Configuration \
    '{"UICulture":"en-US","MetadataCountryCode":"PL","PreferredMetadataLanguage":"en"}')"
  [[ "$code" =~ ^(200|204)$ ]] || hl_die "/Startup/Configuration returned ${code}"

  code="$(post_json /Startup/User \
    "{\"Name\":$(hl_json_escape "$USERNAME"),\"Password\":$(hl_json_escape "$PASSWORD")}")"
  [[ "$code" =~ ^(200|204)$ ]] || hl_die "/Startup/User returned ${code}"

  code="$(post_json /Startup/RemoteAccess \
    '{"EnableRemoteAccess":true,"EnableAutomaticPortMapping":false}')"
  [[ "$code" =~ ^(200|204)$ ]] || hl_warn "/Startup/RemoteAccess returned ${code}"

  code="$(post_json /Startup/Complete '{}')"
  [[ "$code" =~ ^(200|204)$ ]] || hl_die "/Startup/Complete returned ${code}"
}

declared_libraries() {
  python3 - "$(hl_config_dir)/services.yml" <<'PY'
import sys, yaml

doc = yaml.safe_load(open(sys.argv[1]))
service = next(s for s in doc["services"] if s["name"] == "jellyfin")
for library in service.get("libraries", []):
    print("{name}|{type}|{path}".format(**library))
PY
}

ensure_libraries() {
  local token="$1" existing record name type path code
  existing="$(hl_curl -H "X-Emby-Token: ${token}" "${BASE}/Library/VirtualFolders" |
    python3 -c 'import json,sys; print("|".join(f["Name"] for f in json.load(sys.stdin)))')"
  while IFS='|' read -r name type path; do
    [[ -n "$name" ]] || continue
    if [[ "|${existing}|" == *"|${name}|"* ]]; then
      hl_log "library ${name} present"
      continue
    fi
    hl_log "creating library ${name} (${type}) at ${path}"
    docker exec "$CONTAINER" mkdir -p "$path"
    code="$(printf '%s' "{\"LibraryOptions\":{\"PathInfos\":[{\"Path\":\"${path}\"}],\"EnableRealtimeMonitor\":false}}" |
      curl -s -o /dev/null -w '%{http_code}' --max-time 60 -X POST \
        "${BASE}/Library/VirtualFolders?name=${name}&collectionType=${type}&refreshLibrary=false" \
        -H "X-Emby-Token: ${token}" -H 'Content-Type: application/json' --data @-)"
    [[ "$code" =~ ^(200|204)$ ]] || hl_warn "library ${name} rejected (HTTP ${code})"
  done < <(declared_libraries)
}

if [[ "$(wizard_done)" == "false" ]]; then
  run_wizard
  hl_wait_http "${BASE}/System/Info/Public" "200" 90 || hl_die "Jellyfin did not come back after the wizard"
fi

TOKEN="$(login)"
if [[ -z "$TOKEN" ]]; then
  hl_skip "wizard already completed with an unknown password — reset on DEV via docs/kb/apps/jellyfin.md"
fi
hl_log "admin ${USERNAME} authenticated"

ensure_libraries "$TOKEN"
hl_log "OK"
