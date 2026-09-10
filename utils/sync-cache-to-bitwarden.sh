#!/usr/bin/env bash
# Push ~/.homelab-secrets/<env>/* into Bitwarden as Secure Notes.
# Never prints secret values. Requires an unlocked CLI session.
#
#   bw login
#   export BW_SESSION="$(bw unlock --raw)"
#   ./utils/sync-cache-to-bitwarden.sh --env dev
#   ./utils/sync-cache-to-bitwarden.sh --env prod
#   ./utils/sync-cache-to-bitwarden.sh --env all
#
# Item name: homelab/<NAME>/<env>  folder: homelab
# Existing notes with the same name are updated.

set -euo pipefail

CACHE_ROOT="${HOME}/.homelab-secrets"
FOLDER_NAME="homelab"
ENVIRONMENT=""

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENVIRONMENT="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

[[ -n "$ENVIRONMENT" ]] || { echo "--env dev|prod|all is required" >&2; exit 1; }
command -v bw >/dev/null || { echo "bw CLI is not installed" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

if [[ -z "${BW_SESSION:-}" ]]; then
  echo "BW_SESSION is unset. In a TTY:" >&2
  echo "  bw login" >&2
  echo "  export BW_SESSION=\"\$(bw unlock --raw)\"" >&2
  exit 1
fi

status="$(bw status --session "$BW_SESSION" 2>/dev/null | jq -r '.status' || true)"
if [[ "$status" != "unlocked" ]]; then
  echo "bw status is '${status:-unknown}', need unlocked" >&2
  exit 1
fi

bw sync --session "$BW_SESSION" >/dev/null

folder_id="$(bw list folders --session "$BW_SESSION" |
  jq -r --arg n "$FOLDER_NAME" '.[] | select(.name==$n) | .id' | head -1)"
if [[ -z "$folder_id" ]]; then
  folder_id="$(jq -n --arg name "$FOLDER_NAME" '{name:$name}' |
    bw encode --session "$BW_SESSION" |
    bw create folder --session "$BW_SESSION" |
    jq -r '.id')"
  echo "created folder ${FOLDER_NAME}"
fi

sync_env() {
  local env="$1" dir created updated skipped
  dir="${CACHE_ROOT}/${env}"
  created=0
  updated=0
  skipped=0
  if [[ ! -d "$dir" ]]; then
    echo "${env}: no cache at ${dir} — skip"
    return 0
  fi

  local items
  items="$(bw list items --session "$BW_SESSION" --folderid "$folder_id")"

  local file name item_name existing id payload rc
  while IFS= read -r -d '' file; do
    name="$(basename "$file")"
    [[ -s "$file" ]] || { echo "  skip empty ${name}"; skipped=$((skipped + 1)); continue; }
    item_name="homelab/${name}/${env}"
    existing="$(jq -r --arg n "$item_name" '.[] | select(.name==$n) | .id' <<<"$items" | head -1)"

    if [[ -n "$existing" ]]; then
      jq -n --argjson item "$(bw get item "$existing" --session "$BW_SESSION")" \
        --arg notes "$(cat "$file")" \
        --arg folder "$folder_id" \
        '$item | .notes=$notes | .folderId=$folder' |
        bw encode --session "$BW_SESSION" |
        bw edit item "$existing" --session "$BW_SESSION" >/dev/null
      echo "  updated ${item_name}"
      updated=$((updated + 1))
    else
      jq -n \
        --arg name "$item_name" \
        --arg notes "$(cat "$file")" \
        --arg folder "$folder_id" \
        '{type:2, name:$name, notes:$notes, folderId:$folder, secureNote:{type:0}}' |
        bw encode --session "$BW_SESSION" |
        bw create item --session "$BW_SESSION" >/dev/null
      echo "  created ${item_name}"
      created=$((created + 1))
    fi
    unset payload
  done < <(find "$dir" -type f -print0 | sort -z)

  echo "${env}: created=${created} updated=${updated} skipped=${skipped}"
}

case "$ENVIRONMENT" in
  all) sync_env dev; sync_env prod ;;
  dev|prod) sync_env "$ENVIRONMENT" ;;
  *) echo "--env must be dev|prod|all" >&2; exit 1 ;;
esac
