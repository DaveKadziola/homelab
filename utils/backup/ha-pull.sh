#!/usr/bin/env bash
# Pull the newest Home Assistant Supervisor backup from the T620 (F5).
# HAOS is not in this repo — this only copies a .tar if the host answers.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HA="$(hl_storage ha_host)"
if [[ -z "$HA" ]]; then
  echo "ha-pull: no ha_host for ${HOMELAB_ENV} — skip"
  exit 0
fi
if ! ping -c 1 -W 2 "$HA" >/dev/null 2>&1; then
  echo "ha-pull: ${HA} unreachable — skip"
  exit 0
fi

ROOT="$(hl_storage backup_root)/homeassistant"
mkdir -p "$ROOT"
# Supervisor API needs a long-lived token (HA_TOKEN in the secret cache).
TOKEN="$(hl_secret HA_TOKEN)" || { echo "ha-pull: HA_TOKEN missing — skip"; exit 0; }
# List backups, download the newest slug.
slug="$(curl -fsS -H "Authorization: Bearer ${TOKEN}" \
  "http://${HA}:8123/api/hassio/backups" |
  python3 -c 'import json,sys; items=json.load(sys.stdin).get("data",{}).get("backups") or [];
print(items[0]["slug"] if items else "")')"
if [[ -z "$slug" ]]; then
  echo "ha-pull: no supervisor backups on the T620"
  exit 0
fi
dest="${ROOT}/ha-${slug}-$(hl_stamp).tar"
curl -fsS -H "Authorization: Bearer ${TOKEN}" \
  "http://${HA}:8123/api/hassio/backups/${slug}/download" -o "$dest"
hl_prune "$ROOT"
echo "ha-pull: wrote ${dest}"
