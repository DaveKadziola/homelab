#!/usr/bin/env bash
# Push ~/.homelab-secrets/<env>/* into Bitwarden as Secure Notes homelab/<NAME>/<env>.
# Kept for commands in older instructions; the logic lives in utils/bw-store.py.
#
#   export BW_SESSION="$(bw unlock --raw)"
#   ./utils/sync-cache-to-bitwarden.sh --env dev|prod|prod-plan|all [--dry-run]

set -euo pipefail
exec "$(dirname "${BASH_SOURCE[0]}")/bw-store.py" "$@"
