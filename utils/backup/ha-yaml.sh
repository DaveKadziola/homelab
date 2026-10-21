#!/usr/bin/env bash
# Snapshot of the YAML files the Home Assistant UI writes (automations, scripts, scenes,
# configuration.yaml) into the NAS-private root (not NFS, not Samba, not offsite), only when they
# changed; keeps 30. Restore:
# utils/ha.py --env <env> restore-ui --src <dir> --version <stamp> --dry-run (knowledge/apps/homeassistant.md).
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [[ -z "$(hl_storage ha_url)" ]]; then
  echo "ha-yaml: no ha_url for ${HOMELAB_ENV} — skip"
  exit 0
fi
for name in HA_TOKEN HA_SSH_PRIV; do
  if ! hl_secret "$name" >/dev/null; then
    echo "ha-yaml: $name missing — skip"
    exit 0
  fi
done
python3 "$HL_REPO_ROOT/utils/ha.py" --env "$HOMELAB_ENV" export-ui \
  --dest "$(hl_storage nas_private_root)/homeassistant-yaml" --keep 30
