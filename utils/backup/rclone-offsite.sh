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
rclone --config "$cfg" copy "$ROOT" "$REMOTE" --exclude 'media/**'
echo "rclone: copied ${ROOT} -> ${REMOTE}"
