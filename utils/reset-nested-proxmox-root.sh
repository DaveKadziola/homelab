#!/usr/bin/env bash
# Reset nested Proxmox (libvirt VM) root password via qemu-nbd + chroot.
# Run on the laptop (needs sudo once):
#   ./utils/reset-nested-proxmox-root.sh
#
# Writes new password to ~/.homelab-pve-dev-root-pass (mode 600).

set -euo pipefail

LIBVIRT_URI="${LIBVIRT_URI:-qemu:///system}"
VM_NAME="${DEV_PROXMOX_VM_NAME:-Proxmox}"
DISK="${DEV_PROXMOX_DISK:-/home/kdzl/HomeLab/VMs/Proxmox.qcow2}"
VIRSH="virsh -c ${LIBVIRT_URI}"
PASS_FILE="${HOME}/.homelab-pve-dev-root-pass"
MNT=$(mktemp -d /tmp/pve-mnt.XXXXXX)
NBD=/dev/nbd0

cleanup() {
  set +e
  if mountpoint -q "$MNT"; then
    sudo umount -R "$MNT" 2>/dev/null
  fi
  # deactivate LVM from this NBD if present
  sudo vgchange -an pve 2>/dev/null || true
  sudo qemu-nbd -d "$NBD" 2>/dev/null || true
  rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Reset root password for nested ${VM_NAME} ==="

STATE=$($VIRSH domstate "$VM_NAME" 2>/dev/null || echo missing)
if [[ "$STATE" != "shut off" && "$STATE" != "wyłączone" ]]; then
  echo "Shutting down ${VM_NAME}..."
  $VIRSH shutdown "$VM_NAME" 2>/dev/null || true
  for _ in $(seq 1 20); do
    STATE=$($VIRSH domstate "$VM_NAME")
    [[ "$STATE" == "shut off" || "$STATE" == "wyłączone" ]] && break
    sleep 2
  done
  STATE=$($VIRSH domstate "$VM_NAME")
  if [[ "$STATE" != "shut off" && "$STATE" != "wyłączone" ]]; then
    echo "Force destroy..."
    $VIRSH destroy "$VM_NAME"
  fi
fi

NEW_PASS=$(openssl rand -base64 18 | tr -d '/+=' | head -c 20)
printf '%s\n' "$NEW_PASS" > "$PASS_FILE"
chmod 600 "$PASS_FILE"
echo "New password written to ${PASS_FILE}"

sudo modprobe nbd max_part=16
sudo qemu-nbd -d "$NBD" 2>/dev/null || true
sleep 1
sudo qemu-nbd -c "$NBD" -f qcow2 "$DISK"
sleep 2
sudo partprobe "$NBD" || true

echo "Partitions:"
lsblk "$NBD"

# Prefer Proxmox LVM root (pve/root)
ROOT_DEV=""
if sudo pvs 2>/dev/null | grep -q "${NBD}"; then
  sudo vgchange -ay pve
  if [[ -e /dev/pve/root ]]; then
    ROOT_DEV=/dev/pve/root
  fi
fi

# Fallback: largest partition / ext*
if [[ -z "$ROOT_DEV" ]]; then
  for p in ${NBD}p3 ${NBD}p2 ${NBD}p1 ${NBD}p4; do
    if [[ -b "$p" ]] && sudo blkid "$p" 2>/dev/null | grep -qiE 'ext4|xfs'; then
      ROOT_DEV=$p
      break
    fi
  done
fi

if [[ -z "$ROOT_DEV" ]]; then
  echo "ERROR: could not find root filesystem on ${DISK}"
  lsblk -f "$NBD"
  exit 1
fi

echo "Mounting ${ROOT_DEV} -> ${MNT}"
sudo mount "$ROOT_DEV" "$MNT"

# Set password with chpasswd in chroot
echo "root:${NEW_PASS}" | sudo chroot "$MNT" /usr/sbin/chpasswd
echo "root password updated inside guest"

sudo umount "$MNT"
sudo vgchange -an pve 2>/dev/null || true
sudo qemu-nbd -d "$NBD"
trap - EXIT

echo "Starting ${VM_NAME}..."
$VIRSH start "$VM_NAME"
echo ""
echo "Wait ~30s then open https://192.168.122.219:8006"
echo "Login: root@pam"
echo "Password: cat ${PASS_FILE}"
echo ""
echo "Next: create API token, then:"
echo "  export TF_VAR_proxmox_api_token_secret=..."
echo "  export TF_VAR_proxmox_ssh_password=\$(cat ${PASS_FILE})"
echo "  ./utils/dev-apply-local.sh"
