#!/usr/bin/env bash
# Configure Linkwarden headlessly (F7-B).
#
#   1. register the admin declared in config/identities.yml (first user wins)
#   2. verify the NextAuth credentials login
#   3. if the account exists with another password, rewrite the bcrypt hash in
#      Postgres — Linkwarden exposes no admin password reset API
#
# Usage:
#   ./utils/bootstrap/linkwarden.sh --env dev [--host 127.0.0.1]
#
# Exit: 0 configured, 2 container absent, 1 failed.

HL_APP=linkwarden
HL_USAGE_LINES='2,13'
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hl_parse_args "$@"

CONTAINER="$(hl_service linkwarden container)"
PORT="$(hl_service linkwarden port)"
DATABASE="$(hl_service linkwarden database)"
BASE="http://${HOMELAB_HOST}:${PORT}"
EMAIL="$(hl_account linkwarden email)"
USERNAME="$(hl_account linkwarden username)"
PASSWORD="$(hl_secret "$(hl_account linkwarden secret)")"
POSTGRES_CONTAINER="$(hl_service postgres container)"

hl_require_container "$CONTAINER"
hl_wait_http "${BASE}/" "200 307" 120 || hl_die "Linkwarden not answering on ${BASE}"

# NextAuth needs the csrf cookie and its token to accept a credentials login.
# Older installs used username `admin` with an empty email — try both.
login_works() {
  local jar token identity ok=1
  for identity in "$EMAIL" "$USERNAME"; do
    jar="$(mktemp)"
    token="$(hl_curl -c "$jar" "${BASE}/api/v1/auth/csrf" |
      python3 -c 'import json,sys; print(json.load(sys.stdin)["csrfToken"])')"
    HL_PW="$PASSWORD" HL_USER="$identity" HL_TOKEN="$token" python3 -c '
import os, urllib.parse
print(urllib.parse.urlencode({
    "username": os.environ["HL_USER"],
    "password": os.environ["HL_PW"],
    "csrfToken": os.environ["HL_TOKEN"],
    "redirect": "false",
    "json": "true",
}))' |
      hl_curl -b "$jar" -c "$jar" -o /dev/null -X POST "${BASE}/api/v1/auth/callback/credentials" \
        -H 'Content-Type: application/x-www-form-urlencoded' --data @- 2>/dev/null || true
    if grep -qE 'next-auth\.session-token|authjs\.session-token' "$jar"; then
      ok=0
      rm -f "$jar"
      break
    fi
    rm -f "$jar"
  done
  return $ok
}

register() {
  local body code
  body="{\"name\":$(hl_json_escape "$USERNAME"),\"username\":$(hl_json_escape "$USERNAME"),\"email\":$(hl_json_escape "$EMAIL"),\"password\":$(hl_json_escape "$PASSWORD")}"
  code="$(printf '%s' "$body" |
    curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X POST "${BASE}/api/v1/users" \
      -H 'Content-Type: application/json' --data @-)"
  printf '%s' "$code"
}

# Linkwarden stores bcrypt hashes; the running container carries the library.
reset_password_in_db() {
  local hash
  hash="$(docker exec -e HL_PW="$PASSWORD" "$CONTAINER" \
    node -e 'process.stdout.write(require("bcrypt").hashSync(process.env.HL_PW, 10))' 2>/dev/null || true)"
  [[ "$hash" == \$2* ]] || hl_die "cannot compute a bcrypt hash inside ${CONTAINER} — reset the password manually, see docs/kb/apps/linkwarden.md"
  hl_container_running "$POSTGRES_CONTAINER" || hl_die "Postgres container ${POSTGRES_CONTAINER} is not running"
  # A bcrypt hash and an e-mail never contain a quote, so inlining them is safe.
  printf 'UPDATE "User" SET password = %s, email = %s, username = %s WHERE id = (SELECT id FROM "User" ORDER BY id LIMIT 1);\n' \
    "'${hash}'" "'${EMAIL}'" "'${USERNAME}'" |
    docker exec -i -e PGPASSWORD="$(hl_secret POSTGRES_PASSWORD)" "$POSTGRES_CONTAINER" \
      psql -q -U homelab -d "$DATABASE" -v ON_ERROR_STOP=1 >/dev/null ||
    hl_die "could not update the Linkwarden password in Postgres"
}

if login_works; then
  hl_log "admin ${EMAIL} already matches the declared credential"
else
  CODE="$(register)"
  case "$CODE" in
    200|201)
      hl_log "registered admin ${EMAIL}"
      ;;
    400|409)
      hl_log "account exists with a different password — rewriting the stored hash"
      reset_password_in_db
      ;;
    *)
      hl_die "registration failed (HTTP ${CODE})"
      ;;
  esac
  login_works || hl_die "cannot authenticate as ${EMAIL} after configuring the account"
  hl_log "admin ${EMAIL} converged"
fi

hl_log "OK"
