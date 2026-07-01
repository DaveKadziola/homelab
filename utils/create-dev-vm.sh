#!/usr/bin/env bash
# DEPRECATED — use IaC instead:
#   ./utils/ensure-dev-proxmox.sh
#   ./utils/bootstrap-dev-proxmox.sh [--set-token]
#   push homelab-v2 → infra-apply-dev.yml (or local terraform apply dev)
#
# Create homelab-dev Ubuntu VM on libvirt default network (laptop).
# Usage: ./utils/create-dev-vm.sh [--recreate]
# Images live under /tmp/homelab-libvirt (world-readable) for qemu:///system without sudo.
set -euo pipefail

VM_NAME="${VM_NAME:-homelab-dev}"
VM_RAM_MB="${VM_RAM_MB:-4096}"
VM_VCPUS="${VM_VCPUS:-2}"
VM_DISK_GB="${VM_DISK_GB:-20}"
VM_IP="${VM_IP:-192.168.122.50}"
LIBVIRT_URI="${LIBVIRT_URI:-qemu:///system}"
LIBVIRT_IMG_DIR="${LIBVIRT_IMG_DIR:-/tmp/homelab-libvirt}"
CLOUD_IMG="${LIBVIRT_IMG_DIR}/noble-server-cloudimg-amd64.img"
DISK_PATH="${LIBVIRT_IMG_DIR}/${VM_NAME}.qcow2"
SSH_KEY="${HOME}/.ssh/homelab_dev_ed25519"
VIRSH="virsh -c ${LIBVIRT_URI}"

mkdir -p "$LIBVIRT_IMG_DIR"
chmod 755 "$LIBVIRT_IMG_DIR"

if [[ "${1:-}" == "--recreate" ]]; then
  $VIRSH destroy "$VM_NAME" 2>/dev/null || true
  $VIRSH undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
  rm -f "$DISK_PATH"
fi

if $VIRSH dominfo "$VM_NAME" &>/dev/null; then
  echo "VM ${VM_NAME} already exists. Use --recreate to rebuild."
  $VIRSH domifaddr "$VM_NAME" 2>/dev/null || true
  exit 0
fi

if [[ ! -f "$SSH_KEY" ]]; then
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "homelab-dev"
  echo "SSH key: ${SSH_KEY}"
fi

if [[ ! -f "$CLOUD_IMG" ]]; then
  echo "Downloading Ubuntu 24.04 cloud image..."
  curl -fsSL -o "$CLOUD_IMG" \
    "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  chmod 644 "$CLOUD_IMG"
fi

qemu-img create -f qcow2 -F qcow2 -b "$CLOUD_IMG" "$DISK_PATH" "${VM_DISK_GB}G"
chmod 644 "$DISK_PATH"

SEED_DIR=$(mktemp -d)
trap 'rm -rf "$SEED_DIR"' EXIT

cat > "${SEED_DIR}/user-data" <<EOF
#cloud-config
hostname: ${VM_NAME}
manage_etc_hosts: true
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users
    shell: /bin/bash
    ssh_authorized_keys:
      - $(cat "${SSH_KEY}.pub")
package_update: true
packages:
  - docker.io
  - git
  - curl
runcmd:
  - systemctl enable --now docker
  - usermod -aG docker ubuntu
EOF

cat > "${SEED_DIR}/meta-data" <<EOF
instance-id: ${VM_NAME}
local-hostname: ${VM_NAME}
EOF

virt-install \
  --connect "$LIBVIRT_URI" \
  --name "$VM_NAME" \
  --memory "$VM_RAM_MB" \
  --vcpus "$VM_VCPUS" \
  --disk "path=${DISK_PATH},format=qcow2,bus=virtio" \
  --network network=default,model=virtio \
  --os-variant ubuntu24.04 \
  --import \
  --noautoconsole \
  --cloud-init "user-data=${SEED_DIR}/user-data,meta-data=${SEED_DIR}/meta-data"

echo "Waiting for VM network (DHCP)..."
for _ in $(seq 1 60); do
  ADDR=$($VIRSH domifaddr "$VM_NAME" 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d/ -f1 | head -1)
  if [[ -n "$ADDR" ]]; then
    echo "VM IP: ${ADDR} (inventory default: ${VM_IP})"
    echo "Update ansible/environments/dev/hosts.ini if different."
    echo "SSH: ssh -i ${SSH_KEY} ubuntu@${ADDR}"
    exit 0
  fi
  sleep 5
done

echo "VM started; IP not yet visible. Check: virsh -c ${LIBVIRT_URI} domifaddr ${VM_NAME}"
