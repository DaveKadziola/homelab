#!/usr/bin/env bash
# Restore one gzip SQL dump into a database (F5 / C4).
#
#   ./utils/backup/restore-pg.sh --env dev --db homelab --file /path/to.sql.gz
#   ./utils/backup/restore-pg.sh --env dev --db scratch --file ... --create
set -euo pipefail

ENVIRONMENT=""
DB=""
FILE=""
CREATE=false
CONTAINER="${HL_POSTGRES_CONTAINER:-homelab-core-postgres-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENVIRONMENT="$2"; shift 2 ;;
    --db) DB="$2"; shift 2 ;;
    --file) FILE="$2"; shift 2 ;;
    --create) CREATE=true; shift ;;
    --container) CONTAINER="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done
export HOMELAB_ENV="${ENVIRONMENT:?--env required}"
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ -n "$DB" && -f "$FILE" ]] || { echo "--db and --file are required" >&2; exit 1; }
PASS="$(hl_secret POSTGRES_PASSWORD)" || { echo "POSTGRES_PASSWORD missing" >&2; exit 1; }

if $CREATE; then
  docker exec -e PGPASSWORD="$PASS" "$CONTAINER" \
    psql -U homelab -d postgres -c "CREATE DATABASE ${DB};" 2>/dev/null || true
fi
gunzip -c "$FILE" | docker exec -i -e PGPASSWORD="$PASS" "$CONTAINER" \
  psql -U homelab -d "$DB" -v ON_ERROR_STOP=1 >/dev/null
echo "restored ${FILE} -> ${DB}"
