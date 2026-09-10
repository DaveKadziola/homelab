#!/usr/bin/env bash
# vzdump of the apps/NAS VMIDs (F5). Only runs on a Proxmox host that has
# vzdump(1). Nested DEV and the apps guest SKIP.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if ! command -v vzdump >/dev/null 2>&1; then
  echo "vzdump: not on this host (run on physical PVE) — skip"
  exit 0
fi

ROOT="$(hl_storage backup_root)/vzdump"
mkdir -p "$ROOT"
# Default VMIDs from terraform/environments/prod (101 apps, 102 nas).
VMIDS="${VZDUMP_VMIDS:-101 102}"
# shellcheck disable=SC2086
vzdump $VMIDS --mode snapshot --compress zstd --dumpdir "$ROOT" --mailto ''
hl_prune "$ROOT"
echo "vzdump: wrote into ${ROOT}"
