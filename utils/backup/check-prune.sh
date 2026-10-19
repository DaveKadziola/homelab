#!/usr/bin/env bash
# Prove A15 keep=2 without touching real artefacts.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

dir="$(hl_storage backup_root)/.prune-test"
mkdir -p "$dir"
rm -f "$dir"/*
# Same prefix, three stamps — keep=2 must drop the oldest.
touch "$dir/probe-20200101T000000Z"
sleep 0.2
touch "$dir/probe-20200102T000000Z"
sleep 0.2
touch "$dir/probe-20200103T000000Z"
hl_prune "$dir"
n="$(find "$dir" -maxdepth 1 -type f | wc -l)"
left="$(ls -1 "$dir")"
rm -rf "$dir"
if [[ "$n" -ne 2 ]] || [[ "$left" == *20200101T000000Z* ]]; then
  echo "check-prune: expected 2 newest probe-* files, got ${n}: ${left}" >&2
  exit 1
fi
echo "check-prune: ok"
