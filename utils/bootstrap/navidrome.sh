#!/usr/bin/env bash
# Converge the Navidrome admin password (F7-B).
#
# ND_DEVAUTOCREATEADMINPASSWORD only runs on first start. After that the
# `navidrome user edit --set-password` CLI needs a TTY (a pipe fails with
# "inappropriate ioctl for device"), so pexpect drives `docker exec -t`.
#
# Usage:
#   ./utils/bootstrap/navidrome.sh --env dev [--host 127.0.0.1]
#
# Exit: 0 configured, 2 container absent, 1 failed.

HL_APP=navidrome
HL_USAGE_LINES='2,12'
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hl_parse_args "$@"

CONTAINER="$(hl_service navidrome container)"
PORT="$(hl_service navidrome port)"
BASE="http://${HOMELAB_HOST}:${PORT}"
USERNAME="$(hl_account navidrome username)"
PASSWORD="$(hl_secret "$(hl_account navidrome secret)")"

hl_require_container "$CONTAINER"
hl_wait_http "${BASE}/" "200" 60 || hl_die "Navidrome not answering on ${BASE}"

login_works() {
  local code
  code="$(printf '{"username":%s,"password":%s}' \
    "$(hl_json_escape "$USERNAME")" "$(hl_json_escape "$PASSWORD")" |
    curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
      -X POST "${BASE}/auth/login" \
      -H 'Content-Type: application/json' --data @-)"
  [[ "$code" == "200" || "$code" == "201" ]]
}

if login_works; then
  hl_log "admin ${USERNAME} already matches the declared credential"
  hl_log "OK"
  exit 0
fi

hl_log "setting the admin password through navidrome user edit"
HL_CONTAINER="$CONTAINER" HL_USER="$USERNAME" HL_PW="$PASSWORD" python3 - <<'PY' >/dev/null
import os, sys
try:
    import pexpect
except ImportError:
    sys.exit(2)
child = pexpect.spawn(
    "docker",
    [
        "exec", "-it", os.environ["HL_CONTAINER"],
        "/app/navidrome", "user", "edit",
        "-u", os.environ["HL_USER"], "--set-password",
        "--datafolder", "/data",
        "--configfile", "/etc/navidrome/navidrome.toml",
    ],
    encoding="utf-8",
    timeout=60,
)
child.expect("password")
child.sendline(os.environ["HL_PW"])
idx = child.expect(["password", "confirm", pexpect.EOF], timeout=20)
if idx in (0, 1):
    child.sendline(os.environ["HL_PW"])
    child.expect(pexpect.EOF, timeout=20)
sys.exit(0 if child.wait() == 0 else 1)
PY
rc=$?
[[ $rc -eq 2 ]] && hl_die "python3-pexpect is required on the app host for Navidrome password reset"
[[ $rc -eq 0 ]] || hl_die "navidrome user edit --set-password failed"

login_works || hl_die "admin ${USERNAME} still cannot log in after the CLI reset"
hl_log "admin ${USERNAME} converged"
hl_log "OK"
