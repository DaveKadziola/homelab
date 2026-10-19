#!/usr/bin/env bash
# Zip the deployed /opt/homelab tree minus secrets (F5). Not a git bundle —
# enough to recreate compose + config on a new guest.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SRC="${HL_REPO_ROOT:-/opt/homelab}"
if [[ ! -d "$SRC/compose" && ! -d "$SRC/.git" ]]; then
  echo "repo-zip: ${SRC} has no compose/ or .git — skip"
  exit 0
fi

ROOT="$(hl_storage backup_root)/repo-zip"
mkdir -p "$ROOT"
dest="${ROOT}/homelab-$(hl_stamp).zip"
if ! (
  cd "$SRC"
  zip -qr "$dest" . \
    -x './.git/*' \
    -x './secrets/*' \
    -x '*/.env' \
    -x '*/authelia/certs/*'
); then
  echo "repo-zip: zip exited $? — skip"
  rm -f "$dest"
  exit 0
fi
hl_prune "$ROOT"
echo "repo-zip: wrote ${dest}"
