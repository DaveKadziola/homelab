# shellcheck shell=bash
# Shared helpers for utils/backup/*.sh (F5). Never prints secret values.

: "${HOMELAB_ENV:?set HOMELAB_ENV or pass --env}"
HL_REPO_ROOT="${HL_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
HL_CONFIG_DIR="${HOMELAB_CONFIG_DIR:-$HL_REPO_ROOT/config}"
HL_SECRETS_DIR="${HOMELAB_SECRETS_DIR:-${HOME}/.homelab-secrets}"

hl_storage() {
  python3 - "$HL_CONFIG_DIR/storage.yml" "$HOMELAB_ENV" "$@" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
env = sys.argv[2]
st = doc["environments"][env]
cmd = sys.argv[3]
if cmd == "backup_root":
    print(st["backup_root"])
elif cmd == "keep":
    print(doc["retention"]["keep"])
elif cmd == "rclone":
    print("yes" if st.get("rclone") else "no")
elif cmd == "ha_host":
    print(st.get("ha_host") or "")
elif cmd == "offsite":
    print(doc["offsite"]["remote"])
PY
}

hl_secret() {
  local name="$1" path
  if [[ -n "${!name:-}" ]]; then
    printf '%s' "${!name}"
    return
  fi
  path="${HL_SECRETS_DIR}/${HOMELAB_ENV}/${name}"
  [[ -f "$path" ]] || path="${HL_SECRETS_DIR}/${name}"
  [[ -f "$path" ]] || return 1
  tr -d '\r\n' <"$path"
}

hl_prune() {
  local dir="$1" keep
  keep="$(hl_storage keep)"
  [[ -d "$dir" ]] || return 0
  # Keep the $keep newest files *per prefix* (name before -YYYYMMDDTHHMMSSZ).
  # One pg_dump run writes many databases; pruning the directory as a flat
  # list would delete every DB except two files.
  python3 - "$dir" "$keep" <<'PY'
import os, re, sys

directory, keep = sys.argv[1], int(sys.argv[2])
pat = re.compile(r"^(.*)-\d{8}T\d{6}Z")
groups = {}
for name in os.listdir(directory):
    path = os.path.join(directory, name)
    if not os.path.isfile(path):
        continue
    match = pat.match(name)
    key = match.group(1) if match else name
    groups.setdefault(key, []).append((os.path.getmtime(path), path))
for files in groups.values():
    files.sort(reverse=True)
    for _, path in files[keep:]:
        os.remove(path)
PY
}

hl_stamp() { date -u +%Y%m%dT%H%M%SZ; }
