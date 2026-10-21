#!/usr/bin/env bash
# Home Assistant suite — the DEV twin VM or the prod T620, through utils/ha.py
# (config/storage.yml environments.<env>.ha_url).
#
#   api            the API answers to HA_TOKEN
#   config         the core config check is valid
#   revision       sensor.homelab_config_revision names the deployed commit, and its
#                  homeassistant/packages equal this checkout's
#   addon-<slug>   Terminal & SSH and Uptime Kuma are started (prod: a stopped Kuma is SKIP, the
#                  deploy leaves it stopped until the owner claims it, knowledge/monitoring.md)
#
# Read-only. SKIP without HA_TOKEN (prod until the owner created it).

set -uo pipefail

# shellcheck source=../lib/common.sh
source "$HL_REPO_ROOT/tests/lib/common.sh"

ha() { python3 "$HL_REPO_ROOT/utils/ha.py" --env "$HL_ENV" "$@"; }

status_json="$(ha status 2>"$HL_TMP/ha-status.err")"
rc=$?
if [[ $rc -eq 2 ]]; then
  report SKIP "all" "$(tr -d '\n' <"$HL_TMP/ha-status.err")"
  exit 0
elif [[ $rc -ne 0 ]]; then
  report "$(hl_unreachable_status)" "api" "$(tr -d '\n' <"$HL_TMP/ha-status.err")"
  exit 0
fi
core="$(jq -r .core <<<"$status_json")"
report PASS "api" "Home Assistant $core answers"

if ha check >"$HL_TMP/ha-check.out" 2>&1; then
  report PASS "config" "core config check: valid"
else
  report FAIL "config" "$(tr '\n' ' ' <"$HL_TMP/ha-check.out")"
fi

# The deployed packages must equal this checkout's homeassistant/packages. CI checkouts are shallow:
# fetch the deployed commit when it is missing, SKIP when even that fails.
rev="$(jq -r '.revision // ""' <<<"$status_json")"
git_() { git -C "$HL_REPO_ROOT" "$@"; }
if [[ ! "$rev" =~ ^[0-9a-f]{40}$ ]]; then
  report FAIL "revision" "sensor.homelab_config_revision is '${rev:-missing}' (utils/ha.py --env $HL_ENV deploy)"
elif ! git_ cat-file -e "${rev}^{commit}" 2>/dev/null && ! git_ fetch -q --depth=1 origin "$rev" 2>/dev/null; then
  report SKIP "revision" "deployed commit ${rev:0:12} is not in this checkout and cannot be fetched"
elif git_ diff --quiet "$rev" HEAD -- homeassistant/packages; then
  report PASS "revision" "packages of ${rev:0:12} loaded, same as this checkout"
else
  report FAIL "revision" "Home Assistant runs the packages of ${rev:0:12}; homeassistant/packages changed since (deploy pending?)"
fi

for slug in core_ssh a0d7b954_uptime-kuma; do
  state="$(jq -r --arg s "$slug" '.addons[$s] // "missing"' <<<"$status_json")"
  if [[ "$state" == "started" ]]; then
    report PASS "addon-$slug" "started"
  elif [[ "$HL_ENV" == prod && "$slug" == a0d7b954_uptime-kuma && "$state" == stopped ]]; then
    # Supervisor shows no claim: a claimed Kuma that stopped looks the same.
    report SKIP "addon-$slug" "stopped - waits for the owner's claim (knowledge/monitoring.md)"
  else
    report FAIL "addon-$slug" "state $state (utils/ha.py --env $HL_ENV bootstrap)"
  fi
done
