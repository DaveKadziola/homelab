#!/usr/bin/env bash
# Full Home Assistant backup onto the NAS (F5): utils/ha.py makes a Supervisor backup protected with
# HA_BACKUP_PASSWORD, downloads it, deletes it from HA and keeps the newest `retention.keep`.
# Runs on the NAS (run-nas.sh): same IOT subnet as the T620, no firewall rule needed.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [[ -z "$(hl_storage ha_url)" ]]; then
  echo "ha-pull: no ha_url for ${HOMELAB_ENV} — skip"
  exit 0
fi
if ! hl_secret HA_TOKEN >/dev/null; then
  echo "ha-pull: HA_TOKEN missing — skip"
  exit 0
fi
python3 "$HL_REPO_ROOT/utils/ha.py" --env "$HOMELAB_ENV" backup \
  --dest "$(hl_storage nas_backup_root)/homeassistant" --keep "$(hl_storage keep)"
