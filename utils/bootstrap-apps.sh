#!/usr/bin/env bash
# Run every application bootstrap in dependency order (F7-B).
#
# Each utils/bootstrap/<app>.sh converges one app through its own API or CLI and
# is safe to re-run. Apps whose container is not deployed are reported as SKIP,
# not as a failure, so optional compose profiles never break a deploy.
#
# Usage:
#   ./utils/bootstrap-apps.sh --env dev
#   ./utils/bootstrap-apps.sh --env prod --host 192.168.50.30
#   ./utils/bootstrap-apps.sh --env dev --only portainer,immich
#   ./utils/bootstrap-apps.sh --env dev --skip homarr
#
# Exit: 0 when nothing failed, 1 when at least one app failed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_DIR="${ROOT}/utils/bootstrap"

# Dependency order: Portainer owns the stacks, Homarr's board links everything.
APPS=(portainer pgadmin authelia linkwarden immich jellyfin syncthing beszel homarr)

ENVIRONMENT=""
HOST=""
ONLY=""
SKIP=""

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENVIRONMENT="$2"; shift 2 ;;
    --host) HOST="$2"; shift 2 ;;
    --only) ONLY=",${2},"; shift 2 ;;
    --skip) SKIP=",${2},"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

[[ -n "$ENVIRONMENT" ]] || { echo "--env dev|prod is required" >&2; exit 1; }
[[ "$ENVIRONMENT" == "dev" || "$ENVIRONMENT" == "prod" ]] || { echo "--env must be dev or prod" >&2; exit 1; }
command -v docker >/dev/null || { echo "docker is required on the app host" >&2; exit 1; }

export HOMELAB_ENV="$ENVIRONMENT"
[[ -n "$HOST" ]] && export HOMELAB_HOST="$HOST"

declare -a RESULTS=()
failed=0

for app in "${APPS[@]}"; do
  [[ -z "$ONLY" || "$ONLY" == *",${app},"* ]] || continue
  [[ -z "$SKIP" || "$SKIP" != *",${app},"* ]] || { RESULTS+=("${app}|SKIP|excluded with --skip"); continue; }

  script="${BOOTSTRAP_DIR}/${app}.sh"
  if [[ ! -x "$script" ]]; then
    RESULTS+=("${app}|SKIP|no bootstrap script")
    continue
  fi

  echo "── ${app} ─────────────────────────────────────────────"
  set +e
  output="$("$script" --env "$ENVIRONMENT" ${HOST:+--host "$HOST"} 2>&1)"
  rc=$?
  set -e
  printf '%s\n' "$output"

  case "$rc" in
    0) RESULTS+=("${app}|PASS|configured") ;;
    2) RESULTS+=("${app}|SKIP|$(sed -n 's/.*SKIP //p' <<<"$output" | tail -n1)") ;;
    *) RESULTS+=("${app}|FAIL|$(sed -n 's/.*FAIL //p' <<<"$output" | tail -n1)"); failed=$((failed + 1)) ;;
  esac
done

echo
printf '%-12s %-6s %s\n' "APP" "RESULT" "DETAIL"
printf '%-12s %-6s %s\n' "------------" "------" "------------------------------------------"
for result in "${RESULTS[@]}"; do
  IFS='|' read -r app status detail <<<"$result"
  printf '%-12s %-6s %s\n' "$app" "$status" "${detail:-–}"
done
echo
echo "Environment: ${ENVIRONMENT}  Failed: ${failed}"

[[ $failed -eq 0 ]]
