#!/usr/bin/env bash
# Single entrypoint for the homelab test suites (F7-C).
#
#   utils/run-tests.sh --env dev|prod [--suite smoke|infra|net|config|restore|all] [--json]
#
# Every suite is driven by config/services.yml and config/identities.yml, so
# adding a service means editing that file, not this script.
#
# Exit status: 1 if anything FAILed, 0 otherwise. SKIP is not a failure — a
# check that cannot run (physical prod offline, secret not available on this
# machine, tool missing) says so instead of pretending to pass.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUITES_ALL=(smoke infra net config)

ENVIRONMENT=""
SUITE="all"
JSON=0
JSON_OUT=""

usage() {
  cat <<'EOF'
Usage: utils/run-tests.sh --env dev|prod [options]

Options:
  --env <dev|prod>       Environment from config/services.yml (required)
  --suite <name>         smoke | infra | net | config | restore | all
                         (default: all — restore is opt-in, not in all)
  --json                 Print a JSON report on stdout instead of the table
  --json-out <file>      Also write the JSON report to <file> (keeps the table)
  --list                 List the available suites and exit
  -h, --help             This help

Suites:
  smoke   every service in config/services.yml is Up and answering
  infra   terraform/ansible drift, VM size vs tfvars, IP/VLAN vs docs
  net     DNS, WireGuard, public HAProxy endpoint + TLS expiry, firewall paths
  config  GH environment secrets, committed secrets, config vs compose vs docs
  restore F5/C4 scratch dump→restore + NFS/timer (not in --suite all)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENVIRONMENT="${2:-}"; shift 2 ;;
    --env=*) ENVIRONMENT="${1#*=}"; shift ;;
    --suite) SUITE="${2:-}"; shift 2 ;;
    --suite=*) SUITE="${1#*=}"; shift ;;
    --json) JSON=1; shift ;;
    --json-out) JSON_OUT="${2:-}"; shift 2 ;;
    --json-out=*) JSON_OUT="${1#*=}"; shift ;;
    --list) printf '%s\n' "${SUITES_ALL[@]}"; exit 0 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "run-tests: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$ENVIRONMENT" ]]; then
  echo "run-tests: --env dev|prod is required" >&2
  exit 2
fi
if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "prod" ]]; then
  echo "run-tests: unknown environment '$ENVIRONMENT'" >&2
  exit 2
fi

SUITES_KNOWN=("${SUITES_ALL[@]}" restore)
if [[ "$SUITE" == "all" ]]; then
  # restore is monthly / after a backup change — not every push.
  SUITES=("${SUITES_ALL[@]}")
else
  SUITES=()
  for candidate in "${SUITES_KNOWN[@]}"; do
    [[ "$candidate" == "$SUITE" ]] && SUITES=("$candidate")
  done
  if [[ ${#SUITES[@]} -eq 0 ]]; then
    echo "run-tests: unknown suite '$SUITE' (have: ${SUITES_KNOWN[*]} all)" >&2
    exit 2
  fi
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/homelab-tests.XXXXXX")"
RESULTS="$TMP_DIR/results.tsv"
: >"$RESULTS"
cleanup() {
  # Drop the ssh control sockets the suites opened, then the scratch dir.
  local socket
  for socket in "$TMP_DIR"/ssh-*; do
    [[ -S "$socket" ]] && ssh -O exit -o ControlPath="$socket" placeholder 2>/dev/null
  done
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

export HL_REPO_ROOT="$REPO_ROOT"
export HL_ENV="$ENVIRONMENT"
export HL_RESULTS="$RESULTS"
export HL_TMP="$TMP_DIR"
# Kept after the run so a failure can be read afterwards (plan output, ansible log).
export HL_ARTIFACTS="${HL_ARTIFACT_DIR:-${TMPDIR:-/tmp}/homelab-tests-$ENVIRONMENT}"
mkdir -p "$HL_ARTIFACTS"
# Physical prod is built after dev; while it is offline its checks must skip.
export HL_SKIP_WHEN_UNREACHABLE="${HL_SKIP_WHEN_UNREACHABLE:-$([[ "$ENVIRONMENT" == "prod" ]] && echo 1 || echo 0)}"

STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
[[ "$JSON" -eq 1 ]] || {
  echo "homelab tests — env=$ENVIRONMENT suites=${SUITES[*]} started=$STARTED"
  echo "artifacts: $HL_ARTIFACTS"
  echo
}

for suite in "${SUITES[@]}"; do
  runner="$REPO_ROOT/tests/$suite/run.sh"
  if [[ ! -x "$runner" ]]; then
    printf '%s\t%s\t%s\t%s\n' "$suite" FAIL "suite/runner" "missing or not executable: tests/$suite/run.sh" >>"$RESULTS"
    continue
  fi
  if [[ "$JSON" -eq 1 ]]; then
    HL_SUITE="$suite" "$runner" >"$TMP_DIR/$suite.log" 2>&1
  else
    HL_SUITE="$suite" "$runner"
  fi
  rc=$?
  if [[ $rc -ne 0 ]]; then
    printf '%s\t%s\t%s\t%s\n' "$suite" FAIL "suite/runner" "tests/$suite/run.sh exited $rc" >>"$RESULTS"
  fi
  [[ "$JSON" -eq 1 ]] || echo
done

PASS_N=$(awk -F'\t' '$2=="PASS"' "$RESULTS" | wc -l)
FAIL_N=$(awk -F'\t' '$2=="FAIL"' "$RESULTS" | wc -l)
SKIP_N=$(awk -F'\t' '$2=="SKIP"' "$RESULTS" | wc -l)

emit_json() {
  HL_STARTED="$STARTED" python3 - "$RESULTS" "$ENVIRONMENT" <<'PY'
import json, os, sys

results_path, environment = sys.argv[1], sys.argv[2]
records, summary = [], {"pass": 0, "fail": 0, "skip": 0}
with open(results_path, encoding="utf-8") as fh:
    for line in fh:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 4:
            continue
        suite, status, ident, message = parts[0], parts[1], parts[2], "\t".join(parts[3:])
        records.append(
            {"suite": suite, "status": status, "id": ident, "test": f"{suite}/{ident}",
             "message": message}
        )
        summary[status.lower()] = summary.get(status.lower(), 0) + 1
print(json.dumps(
    {"environment": environment, "started": os.environ.get("HL_STARTED", ""),
     "summary": summary, "results": records},
    indent=2,
))
PY
}

[[ -n "$JSON_OUT" ]] && emit_json >"$JSON_OUT"

if [[ "$JSON" -eq 1 ]]; then
  emit_json
else
  echo "================================================================================"
  printf '%-6s %-44s %s\n' STATUS TEST DETAIL
  echo "--------------------------------------------------------------------------------"
  awk -F'\t' '{ printf "%-6s %-44s %s\n", $2, $1"/"$3, $4 }' "$RESULTS"
  echo "--------------------------------------------------------------------------------"
  awk -F'\t' '
    { total[$1]++; count[$1"|"$2]++ }
    END {
      for (suite in total)
        printf "%-8s PASS=%-4d FAIL=%-4d SKIP=%-4d\n", suite,
               count[suite"|PASS"], count[suite"|FAIL"], count[suite"|SKIP"]
    }' "$RESULTS" | sort
  echo "--------------------------------------------------------------------------------"
  printf 'TOTAL    PASS=%-4d FAIL=%-4d SKIP=%-4d   env=%s\n' "$PASS_N" "$FAIL_N" "$SKIP_N" "$ENVIRONMENT"
  echo "================================================================================"
fi

[[ "$FAIL_N" -gt 0 ]] && exit 1
exit 0
