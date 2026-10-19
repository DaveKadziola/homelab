#!/usr/bin/env bash
# Config suite (F7-C / C5) — is the declared configuration the real one?
#
#   gh-secret/<NAME>          every secret named in config/identities.yml exists
#                             in the matching GitHub environment
#   secret-scan/*             no secret values committed (gitleaks, or the
#                             built-in regex scan when gitleaks is absent)
#   default-credentials/*     no literal fallback secret in a deployed file
#   compose/<name>            config/services.yml ports/containers == compose/
#   docs/<name>               markdown port tables == config/services.yml
#
# Pure repository/API inspection: nothing here touches a host.

set -uo pipefail

# shellcheck source=../lib/common.sh
source "$HL_REPO_ROOT/tests/lib/common.sh"

cd "$HL_REPO_ROOT" || exit 1

# --------------------------------------------------------------------------
# declared secrets exist in the GitHub environment
# --------------------------------------------------------------------------
check_gh_secrets() {
  if ! command -v gh >/dev/null 2>&1; then
    report SKIP "gh-secret/all" "gh is not installed — cannot list GitHub environment secrets"
    return
  fi
  if ! gh auth status >/dev/null 2>&1; then
    report SKIP "gh-secret/all" "gh is not authenticated (gh auth login) — cannot list secrets"
    return
  fi
  local existing
  if ! existing="$(gh secret list --env "$HL_ENV" 2>/dev/null | awk '{print $1}')"; then
    report SKIP "gh-secret/all" "cannot read the '$HL_ENV' GitHub environment (permissions or environment missing)"
    return
  fi
  if [[ -z "$existing" ]]; then
    report FAIL "gh-secret/all" "the '$HL_ENV' GitHub environment has no secrets at all"
    return
  fi

  local name why
  while IFS=$'\t' read -r name why; do
    [[ -z "$name" ]] && continue
    if grep -qx "$name" <<<"$existing"; then
      report PASS "gh-secret/$name" "present in GitHub environment '$HL_ENV' ($why)"
    else
      report FAIL "gh-secret/$name" "declared in config/identities.yml ($why) but missing from GitHub environment '$HL_ENV' — run utils/gen-app-credentials.sh --app <app> --env $HL_ENV"
    fi
  done < <(hl_config secrets "$HL_ENV")
}

check_gh_secrets

# --------------------------------------------------------------------------
# committed secrets
# --------------------------------------------------------------------------
if command -v gitleaks >/dev/null 2>&1; then
  log="$HL_ARTIFACTS/gitleaks-$HL_ENV.log"
  if gitleaks detect --no-banner --redact --source "$HL_REPO_ROOT" >"$log" 2>&1; then
    report PASS "secret-scan/gitleaks" "gitleaks detect found no leaks"
  else
    report FAIL "secret-scan/gitleaks" "gitleaks reported findings — see $log"
  fi
else
  hl_note "  (gitleaks not installed — using the built-in regex scan, see tests/README.md)"
fi

while IFS=$'\t' read -r status ident message; do
  [[ -z "$status" ]] && continue
  report "$status" "$ident" "$message"
done < <(hl_config scan-secrets)

# --------------------------------------------------------------------------
# config/services.yml vs compose/ vs docs/
# --------------------------------------------------------------------------
while IFS=$'\t' read -r status ident message; do
  [[ -z "$status" ]] && continue
  report "$status" "$ident" "$message"
done < <(hl_config check-compose)

while IFS=$'\t' read -r status ident message; do
  [[ -z "$status" ]] && continue
  report "$status" "$ident" "$message"
done < <(hl_config check-docs)

exit 0
