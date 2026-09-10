#!/usr/bin/env bash
# Attach SA500 / Purple to ubuntu-nas on the *physical* Proxmox host (F5 / A1).
#
# Terraform creates the NAS root disk only. Whole-disk passthrough is a qm(1)
# call with a by-id path that does not exist on nested DEV and must not be
# guessed. Fill config/storage.yml environments.prod.passthrough[].by_id, then:
#
#   ./utils/pve-attach-nas-disks.sh --env prod
#
# Does nothing when by_id is empty. Never run against nested PVE.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT=""
PVE_HOST="${PVE_HOST:-192.168.20.20}"
PVE_USER="${PVE_USER:-root}"
VMID="${NAS_VMID:-102}"

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENVIRONMENT="$2"; shift 2 ;;
    --host) PVE_HOST="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done
[[ "$ENVIRONMENT" == "prod" ]] || { echo "--env prod is required (refusing nested DEV)" >&2; exit 1; }

mapfile -t DISKS < <(python3 - "$ROOT/config/storage.yml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
for d in doc["environments"]["prod"].get("passthrough") or []:
    by_id = (d.get("by_id") or "").strip()
    if by_id:
        print(f"{d['name']}|{by_id}")
PY
)

if [[ ${#DISKS[@]} -eq 0 ]]; then
  echo "no by_id set in config/storage.yml — attach nothing"
  echo "on the PVE host: ls /dev/disk/by-id"
  exit 0
fi

scsi=1
for row in "${DISKS[@]}"; do
  IFS='|' read -r name by_id <<<"$row"
  echo "qm set ${VMID} -scsi${scsi} ${by_id},backup=0,replicate=0  # ${name}"
  ssh -o BatchMode=yes "${PVE_USER}@${PVE_HOST}" \
    "qm set ${VMID} -scsi${scsi} ${by_id},backup=0,replicate=0"
  scsi=$((scsi + 1))
done
echo "done — reboot ubuntu-nas if the guest does not see the new disks"
