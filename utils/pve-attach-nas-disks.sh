#!/usr/bin/env bash
# Attach SA500 / Purple to ubuntu-nas on the *physical* Proxmox host (F5 / A1).
#
# Terraform creates the NAS root disk only. Whole-disk passthrough is a qm(1)
# call per config/storage.yml environments.prod.passthrough[] row: fixed slot
# scsiN, serial= (the guest finds the disk by it), ssd=1,discard=on for SSDs.
#
#   ./utils/pve-attach-nas-disks.sh --env prod --dry-run
#   ./utils/pve-attach-nas-disks.sh --env prod
#
# Checks first on the host: the by-id path exists, the disk is not mounted or an
# LVM PV there, and the slot is free or already holds the same line (then skip).
# Never formats. Never run against nested PVE.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT=""
DRY_RUN=false
PVE_HOST="${PVE_HOST:-192.168.20.20}"
PVE_USER="${PVE_USER:-root}"
VMID="${NAS_VMID:-102}"
PVE_KEY="${PVE_KEY:-}"   # e.g. ~/.ssh/homelab_dev_ed25519 (root key on the PVE host)

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENVIRONMENT="$2"; shift 2 ;;
    --host) PVE_HOST="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done
[[ "$ENVIRONMENT" == "prod" ]] || { echo "--env prod is required (refusing nested DEV)" >&2; exit 1; }

# slot|by_id|qm drive options|name - validated here, so nothing unchecked reaches the remote shell.
# Captured in a variable (not < <(...)) so a validation exit stops the script.
PLAN="$(python3 - "$ROOT/config/storage.yml" <<'PY'
import re, sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
rows = doc["environments"]["prod"].get("passthrough") or []
slots = set()
for d in rows:
    by_id, serial, slot = str(d.get("by_id") or ""), str(d.get("serial") or ""), d.get("scsi")
    if not re.fullmatch(r"/dev/disk/by-id/[A-Za-z0-9._:-]+", by_id):
        sys.exit(f"{d.get('name')}: by_id must be a full /dev/disk/by-id/ path, got {by_id!r}")
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,20}", serial):
        sys.exit(f"{d.get('name')}: serial must be 1-20 chars [A-Za-z0-9._-], got {serial!r}")
    if not isinstance(slot, int) or not 1 <= slot <= 30 or slot in slots:
        sys.exit(f"{d.get('name')}: scsi must be a unique slot 1-30 (scsi0 is the root disk), got {slot!r}")
    slots.add(slot)
    opts = f"backup=0,replicate=0,serial={serial}" + (",ssd=1,discard=on" if d.get("ssd") else "")
    print(f"{slot}|{by_id}|{opts}|{d['name']}")
PY
)"
mapfile -t DISKS < <(printf '%s\n' "$PLAN" | sed '/^$/d')

if [[ ${#DISKS[@]} -eq 0 ]]; then
  echo "no passthrough rows in config/storage.yml — attach nothing"
  exit 0
fi

pve() { ssh -o BatchMode=yes ${PVE_KEY:+-i "$PVE_KEY"} "${PVE_USER}@${PVE_HOST}" "$@"; }

for row in "${DISKS[@]}"; do
  IFS='|' read -r slot by_id opts name <<<"$row"
  want="${by_id},${opts}"
  # One remote check per disk; prints the verdict as its last line.
  verdict="$(pve "sh -s" <<EOF
set -u
qm config ${VMID} >/dev/null 2>&1 || { echo "missing: VM ${VMID} does not exist (terraform apply first)"; exit 0; }
dev=\$(readlink -f '${by_id}') || { echo "missing: ${by_id} not on host"; exit 0; }
[ -b "\$dev" ] || { echo "missing: ${by_id} is not a block device"; exit 0; }
if lsblk -nro MOUNTPOINT "\$dev" | grep -q .; then echo "busy: \$dev has a mounted filesystem on the host"; exit 0; fi
if pvs --noheadings -o pv_name 2>/dev/null | grep -q "\$dev"; then echo "busy: \$dev is an LVM PV on the host"; exit 0; fi
cur=\$(qm config ${VMID} | sed -n 's/^scsi${slot}: //p')
other=\$(qm config ${VMID} | grep -E '^(scsi|sata|virtio|ide)[0-9]+: ${by_id}(,|\$)' | grep -v '^scsi${slot}:' || true)
[ -n "\$other" ] && { echo "busy: already attached as \${other%%:*}"; exit 0; }
[ -z "\$cur" ] && { echo "free"; exit 0; }
[ "\$cur" = "${want}" ] && { echo "same"; exit 0; }
echo "taken: scsi${slot} holds \$cur"
EOF
)"
  verdict="${verdict##*$'\n'}"
  case "$verdict" in
    same) echo "skip   ${name}: scsi${slot} already ${want}" ;;
    free)
      echo "attach ${name}: qm set ${VMID} -scsi${slot} ${want}"
      $DRY_RUN || pve "qm set ${VMID} -scsi${slot} '${want}'"
      ;;
    *) echo "STOP   ${name}: ${verdict}" >&2; exit 1 ;;
  esac
done
$DRY_RUN && echo "dry run - nothing changed" || echo "done — reboot ubuntu-nas if the guest does not see the new disks"
