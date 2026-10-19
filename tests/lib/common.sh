# shellcheck shell=bash
# Shared helpers for the homelab test suites (F7-C).
#
# Sourced by tests/<suite>/run.sh, which is always started by
# utils/run-tests.sh — that is what exports HL_ENV, HL_SUITE, HL_RESULTS
# and HL_REPO_ROOT.
#
# A suite never decides how results are rendered: it only calls
#   report PASS|FAIL|SKIP <id> <message>
# and utils/run-tests.sh turns the collected records into a table or JSON.

: "${HL_REPO_ROOT:?set by utils/run-tests.sh}"
: "${HL_ENV:?set by utils/run-tests.sh}"
: "${HL_SUITE:?set by utils/run-tests.sh}"
: "${HL_RESULTS:?set by utils/run-tests.sh}"

HL_TMP="${HL_TMP:-${TMPDIR:-/tmp}}"
# Field separator of `hlconfig.py services` records — a tab would be collapsed
# by `read` (IFS whitespace) and shift the columns of every service that omits
# an optional key such as `path` or `profile`.
HL_FS=$'\x1f'
HL_CFG="$HL_REPO_ROOT/tests/lib/hlconfig.py"
HL_SSH_TIMEOUT="${HL_SSH_TIMEOUT:-8}"
HL_HTTP_TIMEOUT="${HL_HTTP_TIMEOUT:-15}"
# Number of container restarts that still counts as "not a restart loop".
HL_RESTART_LIMIT="${HL_RESTART_LIMIT:-3}"
# 1 = a host we cannot reach makes checks SKIP instead of FAIL (physical prod).
HL_SKIP_WHEN_UNREACHABLE="${HL_SKIP_WHEN_UNREACHABLE:-0}"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  HL_C_PASS=$'\033[32m'; HL_C_FAIL=$'\033[31m'; HL_C_SKIP=$'\033[33m'
  HL_C_DIM=$'\033[2m'; HL_C_OFF=$'\033[0m'
else
  HL_C_PASS=""; HL_C_FAIL=""; HL_C_SKIP=""; HL_C_DIM=""; HL_C_OFF=""
fi

hl_note() { printf '%s%s%s\n' "$HL_C_DIM" "$*" "$HL_C_OFF"; }

hl_config() { python3 "$HL_CFG" "$@"; }

# report <PASS|FAIL|SKIP> <id> <message...>
report() {
  local status="$1" ident="$2"
  shift 2
  local message="$*"
  message="${message//$'\t'/ }"
  message="${message//$'\n'/ }"
  printf '%s\t%s\t%s\t%s\n' "$HL_SUITE" "$status" "$ident" "$message" >>"$HL_RESULTS"
  local colour=""
  case "$status" in
    PASS) colour="$HL_C_PASS" ;;
    FAIL) colour="$HL_C_FAIL" ;;
    SKIP) colour="$HL_C_SKIP" ;;
  esac
  printf '%s%-4s%s %-44s %s\n' "$colour" "$status" "$HL_C_OFF" "$HL_SUITE/$ident" "$message"
}

# Status to use when the target host cannot be reached: prod is expected to be
# offline while it is being built, dev must be up.
hl_unreachable_status() {
  [[ "$HL_SKIP_WHEN_UNREACHABLE" == "1" ]] && echo SKIP || echo FAIL
}

# Loads HL_HOST / HL_SSH_USER / HL_SSH_KEY / HL_INVENTORY from
# config/services.yml + the environment's inventory.
hl_env_load() {
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    export "${line?}"
  done < <(hl_config env "$HL_ENV")
  : "${HL_HOST:?no host for env $HL_ENV in config/services.yml}"
}

# The prod runner lives on the prod app host itself, so "remote" commands would
# have to ssh to their own address. Detect that and run them directly.
hl_target_is_local() {
  if [[ -z "${HL_TARGET_LOCAL:-}" ]]; then
    if ip -o -4 addr show 2>/dev/null | grep -qw "$HL_HOST"; then
      HL_TARGET_LOCAL=yes
    else
      HL_TARGET_LOCAL=no
    fi
    export HL_TARGET_LOCAL
  fi
  [[ "$HL_TARGET_LOCAL" == "yes" ]]
}

hl_ssh() {
  if hl_target_is_local; then
    bash -c "$*"
    return
  fi
  local opts=(
    -o BatchMode=yes
    -o ConnectTimeout="$HL_SSH_TIMEOUT"
    -o StrictHostKeyChecking=accept-new
    -o LogLevel=ERROR
    -o ControlMaster=auto
    -o ControlPath="$HL_TMP/ssh-%C"
    -o ControlPersist=120
  )
  [[ -n "${HL_SSH_KEY:-}" ]] && opts+=(-i "$HL_SSH_KEY")
  ssh "${opts[@]}" "${HL_SSH_USER}@${HL_HOST}" "$@"
}

# Cached "can we log in to the target host at all?"
hl_host_up() {
  if [[ -z "${HL_HOST_UP:-}" ]]; then
    if hl_ssh true >/dev/null 2>&1; then HL_HOST_UP=yes; else HL_HOST_UP=no; fi
    export HL_HOST_UP
  fi
  [[ "$HL_HOST_UP" == "yes" ]]
}

# hl_tcp <host> <port> [timeout]
hl_tcp() {
  local host="$1" port="$2" timeout="${3:-5}"
  timeout "$timeout" bash -c "exec 3<>/dev/tcp/${host}/${port}" 2>/dev/null
}

# hl_http_code <url>  — prints the status code, 000 when unreachable
hl_http_code() {
  curl -s -k -o /dev/null -m "$HL_HTTP_TIMEOUT" -w '%{http_code}' "$1" 2>/dev/null || echo 000
}

# hl_in_list <needle> <comma-separated list>
hl_in_list() {
  local needle="$1" list="$2" item
  local IFS=','
  for item in $list; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}
