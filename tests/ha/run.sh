#!/usr/bin/env bash
# Home Assistant suite — the DEV twin VM or the prod T620, through utils/ha.py
# (config/storage.yml environments.<env>.ha_url).
#
#   api            the API answers to HA_TOKEN
#   config         the core config check is valid
#   revision       sensor.homelab_config_revision holds a commit of this repository, i.e.
#                  homeassistant/packages was deployed and loaded
#   addon-<slug>   Terminal & SSH and Uptime Kuma are started
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

rev="$(jq -r '.revision // ""' <<<"$status_json")"
if [[ "$rev" =~ ^[0-9a-f]{40}$ ]] && git -C "$HL_REPO_ROOT" merge-base --is-ancestor "$rev" HEAD 2>/dev/null; then
  report PASS "revision" "packages from ${rev:0:12} loaded"
else
  report FAIL "revision" "sensor.homelab_config_revision is '${rev:-missing}', not a commit of this checkout (utils/ha.py --env $HL_ENV deploy)"
fi

for slug in core_ssh a0d7b954_uptime-kuma; do
  state="$(jq -r --arg s "$slug" '.addons[$s] // "missing"' <<<"$status_json")"
  if [[ "$state" == "started" ]]; then
    report PASS "addon-$slug" "started"
  else
    report FAIL "addon-$slug" "state $state (utils/ha.py --env $HL_ENV bootstrap)"
  fi
done
