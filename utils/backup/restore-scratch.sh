#!/usr/bin/env bash
# Non-destructive C4 proof: create, dump, drop, restore a throwaway database.
# Never touches application databases.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CONTAINER="${HL_POSTGRES_CONTAINER:-homelab-core-postgres-1}"
DB="f5_restore_scratch"
TOKEN="f5-$(hl_stamp)"
PASS="$(hl_secret POSTGRES_PASSWORD)" || { echo "POSTGRES_PASSWORD missing" >&2; exit 1; }

psql_c() {
  docker exec -e PGPASSWORD="$PASS" "$CONTAINER" \
    psql -U homelab -d postgres -v ON_ERROR_STOP=1 "$@"
}

psql_c -c "DROP DATABASE IF EXISTS ${DB};"
psql_c -c "CREATE DATABASE ${DB};"
docker exec -e PGPASSWORD="$PASS" "$CONTAINER" \
  psql -U homelab -d "$DB" -v ON_ERROR_STOP=1 \
  -c "CREATE TABLE probe(id int PRIMARY KEY, token text NOT NULL);" \
  -c "INSERT INTO probe(id, token) VALUES (1, '${TOKEN}');"

tmp="$(mktemp --suffix=.sql.gz)"
trap 'rm -f "$tmp"' EXIT
docker exec -e PGPASSWORD="$PASS" "$CONTAINER" \
  pg_dump -U homelab --no-owner --format=plain "$DB" | gzip -c >"$tmp"

psql_c -c "DROP DATABASE ${DB};"
psql_c -c "CREATE DATABASE ${DB};"
gunzip -c "$tmp" | docker exec -i -e PGPASSWORD="$PASS" "$CONTAINER" \
  psql -U homelab -d "$DB" -v ON_ERROR_STOP=1 >/dev/null

got="$(docker exec -e PGPASSWORD="$PASS" "$CONTAINER" \
  psql -U homelab -d "$DB" -Atc "SELECT token FROM probe WHERE id = 1;")"
psql_c -c "DROP DATABASE ${DB};"

if [[ "$got" != "$TOKEN" ]]; then
  echo "restore-scratch: expected ${TOKEN}, got ${got:-empty}" >&2
  exit 1
fi
echo "restore-scratch: ok"
