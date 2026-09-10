#!/usr/bin/env bash
# Finish the pCloud rclone remote after OAuth (A9 / F5).
# Never prints rclone.conf or tokens.
#
#   # one-time, interactive — opens a browser:
#   rclone config create pcloud pcloud
#   # then:
#   ./utils/setup-rclone-pcloud.sh
#   ./utils/setup-rclone-pcloud.sh --push-gh   # GH env prod only
#
# Does not enable rclone on DEV (storage.yml rclone: false).

set -euo pipefail

CONF="${RCLONE_CONFIG_FILE:-${HOME}/.config/rclone/rclone.conf}"
REMOTE="${RCLONE_REMOTE:-pcloud}"
ROOT_PATH="${RCLONE_ROOT:-homelab-backups}"
REPO="${GITHUB_REPO:-DaveKadziola/homelab}"
PUSH_GH=false

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push-gh) PUSH_GH=true; shift ;;
    --remote) REMOTE="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

command -v rclone >/dev/null || { echo "rclone is not installed" >&2; exit 1; }

if [[ ! -s "$CONF" ]] || ! grep -q "^\[${REMOTE}\]" "$CONF"; then
  echo "no [${REMOTE}] section in ${CONF}" >&2
  echo "run (interactive, browser OAuth):" >&2
  echo "  rclone config create ${REMOTE} pcloud" >&2
  echo "then re-run this script" >&2
  exit 1
fi

echo "remote ${REMOTE}: present (config ${#CONF} path, not printed)"

rclone mkdir "${REMOTE}:${ROOT_PATH}"
for sub in vzdump postgres volumes homeassistant opnsense repo-zip; do
  rclone mkdir "${REMOTE}:${ROOT_PATH}/${sub}"
done

echo "listing ${REMOTE}:${ROOT_PATH} (names only)"
rclone lsd "${REMOTE}:${ROOT_PATH}"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
printf 'ok\n' >"$tmp"
rclone copy "$tmp" "${REMOTE}:${ROOT_PATH}/" --include "$(basename "$tmp")"
# The dest name is the temp basename; delete it after a list check.
if rclone ls "${REMOTE}:${ROOT_PATH}/$(basename "$tmp")" >/dev/null; then
  rclone delete "${REMOTE}:${ROOT_PATH}/$(basename "$tmp")"
  echo "round-trip upload/delete: ok"
else
  echo "upload test failed" >&2
  exit 1
fi

umask 077
mkdir -p "${HOME}/.homelab-secrets/prod"
cp "$CONF" "${HOME}/.homelab-secrets/prod/RCLONE_CONFIG"
chmod 600 "${HOME}/.homelab-secrets/prod/RCLONE_CONFIG"
echo "copied rclone.conf → ~/.homelab-secrets/prod/RCLONE_CONFIG (for Bitwarden sync)"

if $PUSH_GH; then
  command -v gh >/dev/null || { echo "gh CLI required for --push-gh" >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "gh is not authenticated" >&2; exit 1; }
  base64 -w0 "$CONF" | gh secret set RCLONE_CONFIG --env prod --repo "$REPO" --body -
  echo "set GitHub environment secret RCLONE_CONFIG (prod)"
fi
