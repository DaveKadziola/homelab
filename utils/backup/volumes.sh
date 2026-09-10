#!/usr/bin/env bash
# Tar named Docker volumes that are not media libraries (F5).
# Immich/Jellyfin/Navidrome libraries live on NFS (prod) or are too large;
# they are not duplicated here (A15 / pCloud media already exists separately).
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT="$(hl_storage backup_root)/volumes"
mkdir -p "$ROOT"
STAMP="$(hl_stamp)"

# State, not libraries.
VOLUMES=(
  homelab-core_portainer_data
  homelab-core_homarr_data
  homelab-core_trilium_data
  homelab-core_actual_data
  homelab-core_linkwarden_data
  homelab-core_syncthing_data
)

ok=0
for vol in "${VOLUMES[@]}"; do
  docker volume inspect "$vol" >/dev/null 2>&1 || continue
  dest="${ROOT}/${vol}-${STAMP}.tar.gz"
  src="/var/lib/docker/volumes/${vol}/_data"
  if [[ -d "$src" ]]; then
    tar -C "$src" -czf "$dest" .
  else
    echo "volumes: ${vol} has no host path — skip"
    continue
  fi
  echo "wrote ${dest}"
  ok=$((ok + 1))
done

hl_prune "$ROOT"
echo "volumes: ${ok} tars, keep=$(hl_storage keep)"
