#!/usr/bin/env bash
# Restore one gzip SQL dump into a database (F5 / C4).
#
#   ./utils/backup/restore-pg.sh --env dev --db homelab --file /path/to.sql.gz
#   ./utils/backup/restore-pg.sh --env dev --db scratch --file ... --create
#   ./utils/backup/restore-pg.sh --env dev --db linkwarden --file ... --replace --owner linkwarden
#   ./utils/backup/restore-pg.sh --env dev --db immich --file ... --replace \
#       --container homelab-core-immich-postgres-1 --user postgres --password-secret IMMICH_DB_PASSWORD
#
# The dumps are plain SQL from `pg_dump --no-owner` without --clean, so they only load into an
# empty database:
#   --create             create the database when it does not exist
#   --replace            drop the database (WITH (FORCE): open connections are closed) and create it
#                        empty. Stop the app first, or it reconnects to a half-restored database.
#   --owner ROLE         create the database owned by ROLE and load the dump as ROLE (SET ROLE), so
#                        the app that connects as ROLE owns its tables again. linkwarden needs this.
#   --user / --password-secret   connect as another user (immich's own Postgres: postgres /
#                        IMMICH_DB_PASSWORD). Defaults: homelab / POSTGRES_PASSWORD.
# The password reaches the container through the environment, never through argv.
set -euo pipefail

ENVIRONMENT=""
DB=""
FILE=""
CREATE=false
REPLACE=false
OWNER=""
PGUSER_NAME="homelab"
PASSWORD_SECRET="POSTGRES_PASSWORD"
CONTAINER="${HL_POSTGRES_CONTAINER:-homelab-core-postgres-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENVIRONMENT="$2"; shift 2 ;;
    --db) DB="$2"; shift 2 ;;
    --file) FILE="$2"; shift 2 ;;
    --create) CREATE=true; shift ;;
    --replace) REPLACE=true; shift ;;
    --owner) OWNER="$2"; shift 2 ;;
    --container) CONTAINER="$2"; shift 2 ;;
    --user) PGUSER_NAME="$2"; shift 2 ;;
    --password-secret) PASSWORD_SECRET="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done
export HOMELAB_ENV="${ENVIRONMENT:?--env required}"
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ -n "$DB" && -f "$FILE" ]] || { echo "--db and --file are required" >&2; exit 1; }
[[ "$DB" =~ ^[a-z_][a-z0-9_]*$ ]] || { echo "invalid database name: ${DB}" >&2; exit 1; }
[[ -z "$OWNER" || "$OWNER" =~ ^[a-z_][a-z0-9_]*$ ]] || { echo "invalid role name: ${OWNER}" >&2; exit 1; }
PGPASSWORD="$(hl_secret "$PASSWORD_SECRET")" || { echo "${PASSWORD_SECRET} missing" >&2; exit 1; }
export PGPASSWORD

psql_admin() {
  docker exec -i -e PGPASSWORD "$CONTAINER" psql -U "$PGUSER_NAME" -d postgres -v ON_ERROR_STOP=1 -q "$@"
}

owner_clause=""
[[ -n "$OWNER" ]] && owner_clause=" OWNER ${OWNER}"

if $REPLACE; then
  psql_admin -c "DROP DATABASE IF EXISTS ${DB} WITH (FORCE);"
  psql_admin -c "CREATE DATABASE ${DB}${owner_clause};"
elif $CREATE; then
  exists="$(psql_admin -Atc "SELECT 1 FROM pg_database WHERE datname = '${DB}'")"
  [[ "$exists" == "1" ]] || psql_admin -c "CREATE DATABASE ${DB}${owner_clause};"
fi

{
  [[ -n "$OWNER" ]] && printf 'SET ROLE %s;\n' "$OWNER"
  gunzip -c "$FILE"
} | docker exec -i -e PGPASSWORD "$CONTAINER" \
  psql -U "$PGUSER_NAME" -d "$DB" -v ON_ERROR_STOP=1 >/dev/null
unset PGPASSWORD
echo "restored ${FILE} -> ${DB}${OWNER:+ (owner ${OWNER})}"
