#!/usr/bin/env bash
# Configure Homarr headlessly (F7-B).
#
#   1. set the credentials admin password through the bundled homarr-cli
#   2. seed the board from compose/core/homarr/board-<env>.json, which
#      utils/gen-homarr-board.sh generates out of config/services.yml
#
# Homarr keeps everything in its own SQLite database and exposes no board API,
# so the seed is written straight into that database while the app is stopped.
# Rows carry deterministic IDs, so re-running replaces them instead of piling
# up duplicates.
#
# Usage:
#   ./utils/bootstrap/homarr.sh --env dev [--host 127.0.0.1]
#
# Exit: 0 configured, 2 container absent, 1 failed.

HL_APP=homarr
HL_USAGE_LINES='2,16'
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hl_parse_args "$@"

CONTAINER="$(hl_service homarr container)"
PORT="$(hl_service homarr port)"
BASE="http://${HOMELAB_HOST}:${PORT}"
USERNAME="$(hl_account homarr username)"
PASSWORD="$(hl_secret "$(hl_account homarr secret)")"
SEED="$(hl_compose_dir)/core/homarr/board-${HOMELAB_ENV}.json"
DB_PATH=/appdata/db/db.sqlite

hl_require_container "$CONTAINER"
hl_wait_http "${BASE}/" "200 307" 120 || hl_die "Homarr not answering on ${BASE}"

# The CLI blocks when stdin is an exhausted pipe, hence the explicit /dev/null.
homarr_cli() {
  timeout 20 docker exec -i "$CONTAINER" \
    sh -c "cd /app && node apps/cli/cli.cjs $*" </dev/null 2>/dev/null
}

login_works() {
  local jar token ok=1
  jar="$(mktemp)"
  token="$(hl_curl -c "$jar" "${BASE}/api/auth/csrf" |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["csrfToken"])')"
  HL_PW="$PASSWORD" HL_USER="$USERNAME" HL_TOKEN="$token" python3 -c '
import os, urllib.parse
print(urllib.parse.urlencode({
    "name": os.environ["HL_USER"],
    "credentialType": "basic",
    "password": os.environ["HL_PW"],
    "csrfToken": os.environ["HL_TOKEN"],
    "redirect": "false",
    "json": "true",
}))' |
    hl_curl -b "$jar" -c "$jar" -o /dev/null -X POST "${BASE}/api/auth/callback/credentials" \
      -H 'Content-Type: application/x-www-form-urlencoded' --data @- 2>/dev/null || true
  grep -qE 'authjs\.session-token|next-auth\.session-token' "$jar" && ok=0
  rm -f "$jar"
  return $ok
}

ensure_admin() {
  local users
  users="$(homarr_cli users list || true)"
  if ! grep -qE "[[:space:]]${USERNAME}([[:space:]]|$)" <<<"$users"; then
    hl_log "no ${USERNAME} user — recreating it"
    homarr_cli recreate-admin -u "$USERNAME" >/dev/null ||
      hl_die "homarr-cli recreate-admin failed — see docs/kb/apps/homarr.md"
  fi
  hl_log "setting the password of ${USERNAME}"
  # The value is expanded inside the container, not on this host's argv.
  docker exec -e HL_PW="$PASSWORD" "$CONTAINER" \
    sh -c 'cd /app && node apps/cli/cli.cjs users update-password -u '"$USERNAME"' -p "$HL_PW"' \
    </dev/null >/dev/null 2>&1 || hl_die "homarr-cli users update-password failed"
}

apply_board_seed() {
  local workdir
  if [[ ! -f "$SEED" ]]; then
    hl_warn "no board seed at ${SEED} — run utils/gen-homarr-board.sh --env ${HOMELAB_ENV}"
    return 0
  fi
  workdir="$(mktemp -d)"
  docker cp "${CONTAINER}:${DB_PATH}" "${workdir}/db.sqlite" >/dev/null

  if python3 "${HL_LIB_DIR}/homarr_board.py" --check "${workdir}/db.sqlite" "$SEED"; then
    hl_log "board already matches the seed"
    rm -rf "$workdir"
    return 0
  fi

  hl_log "seeding the board from $(basename "$SEED")"
  docker stop "$CONTAINER" >/dev/null
  docker cp "${CONTAINER}:${DB_PATH}" "${workdir}/db.sqlite" >/dev/null
  python3 "${HL_LIB_DIR}/homarr_board.py" "${workdir}/db.sqlite" "$SEED" ||
    { docker start "$CONTAINER" >/dev/null; rm -rf "$workdir"; hl_die "board seeding failed"; }
  docker cp "${workdir}/db.sqlite" "${CONTAINER}:${DB_PATH}" >/dev/null
  docker start "$CONTAINER" >/dev/null
  rm -rf "$workdir"
  hl_wait_http "${BASE}/" "200 307" 120 || hl_die "Homarr did not come back after seeding"
}

if login_works; then
  hl_log "admin ${USERNAME} already matches the declared credential"
  apply_board_seed
  hl_log "OK"
  exit 0
fi

if ! timeout 15 docker exec "$CONTAINER" true >/dev/null 2>&1; then
  hl_skip "Homarr container is not answering docker exec"
fi

# homarr-cli (users list / update-password) blocks forever on this image —
# do not wait on it. Board seed still applies; password is set from the UI once.
hl_warn "homarr-cli hangs on this image — skip password converge (use the UI once)"
apply_board_seed
hl_skip "admin password not verifiable via API/CLI — set it once in the Homarr UI"
