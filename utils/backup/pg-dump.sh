#!/usr/bin/env bash
# Dump every user database on the shared Postgres (F5). Retention A15.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CONTAINER="${HL_POSTGRES_CONTAINER:-homelab-core-postgres-1}"
ROOT="$(hl_storage backup_root)/postgres"
mkdir -p "$ROOT"
STAMP="$(hl_stamp)"
PASS="$(hl_secret POSTGRES_PASSWORD)" || { echo "pg-dump: POSTGRES_PASSWORD missing" >&2; exit 1; }

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "pg-dump: container ${CONTAINER} not on this host — skip"
  exit 0
fi

mapfile -t DBS < <(docker exec -e PGPASSWORD="$PASS" "$CONTAINER" \
  psql -U homelab -d postgres -Atc \
  "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres');")

ok=0
for db in "${DBS[@]}"; do
  [[ -n "$db" ]] || continue
  dest="${ROOT}/${db}-${STAMP}.sql.gz"
  docker exec -e PGPASSWORD="$PASS" "$CONTAINER" \
    pg_dump -U homelab --no-owner --format=plain "$db" |
    gzip -c >"$dest"
  echo "wrote ${dest}"
  ok=$((ok + 1))
done

# Immich has its own Postgres.
if docker inspect homelab-core-immich-postgres-1 >/dev/null 2>&1; then
  IPASS="$(hl_secret IMMICH_DB_PASSWORD)" || IPASS="$PASS"
  dest="${ROOT}/immich-${STAMP}.sql.gz"
  docker exec -e PGPASSWORD="$IPASS" homelab-core-immich-postgres-1 \
    pg_dump -U postgres --no-owner --format=plain immich |
    gzip -c >"$dest"
  echo "wrote ${dest}"
  ok=$((ok + 1))
fi

hl_prune "$ROOT"
echo "pg-dump: ${ok} dumps, keep=$(hl_storage keep)"
