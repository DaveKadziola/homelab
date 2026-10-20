#!/usr/bin/env bash
# Copy local backup streams to pCloud (DR only — no media libraries).
# Skips when storage.yml says rclone: false (DEV) or RCLONE_CONFIG is missing.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [[ "$(hl_storage rclone)" != "yes" ]]; then
  echo "rclone: disabled for ${HOMELAB_ENV}"
  exit 0
fi

cfg="$(mktemp)"
trap 'rm -f "$cfg"' EXIT
if ! hl_secret RCLONE_CONFIG >"$cfg" 2>/dev/null; then
  echo "rclone: RCLONE_CONFIG missing — skip offsite (A9 still interactive)"
  exit 0
fi
# Secret may be raw rclone.conf or base64 of it.
if ! grep -q '^\[' "$cfg" 2>/dev/null; then
  base64 -d "$cfg" >"${cfg}.dec" 2>/dev/null && mv "${cfg}.dec" "$cfg"
fi
if ! grep -q '^\[' "$cfg"; then
  echo "rclone: config is not an rclone.conf — skip"
  exit 0
fi
chmod 600 "$cfg"

ROOT="$(hl_storage backup_root)"
REMOTE="$(hl_storage offsite)"
# Plain pCloud would hold DB dumps and volume tars (app data, credentials) in the clear.
section="${REMOTE%%:*}"
if ! awk -v s="[$section]" '$0==s {f=1; next} /^\[/ {f=0} f && /^type *= *crypt *$/ {ok=1} END {exit !ok}' "$cfg"; then
  echo "rclone: remote ${section} is not an rclone crypt remote — skip offsite (knowledge/backup.md)"
  exit 0
fi
filters=()
while IFS= read -r stream; do
  [[ -n "$stream" ]] && filters+=(--include "/${stream}/**")
done < <(hl_storage offsite_include)
[[ ${#filters[@]} -gt 0 ]] || { echo "rclone: offsite.include is empty — skip"; exit 0; }
rclone --config "$cfg" copy "$ROOT" "$REMOTE" "${filters[@]}"
# Freshness marker for check-fresh.py on the NAS (stream offsite in config/monitoring.yml).
date -u +%Y-%m-%dT%H:%M:%SZ >"$ROOT/.offsite-ok"
echo "rclone: copied ${ROOT} -> ${REMOTE}"
