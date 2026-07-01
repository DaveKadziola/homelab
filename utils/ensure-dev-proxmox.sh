#!/usr/bin/env bash
# Start libvirt VM "Proxmox" (nested PVE) if stopped — required for dev TF / :8006 GUI.
set -euo pipefail

LIBVIRT_URI="${LIBVIRT_URI:-qemu:///system}"
VM_NAME="${DEV_PROXMOX_VM_NAME:-Proxmox}"
VIRSH="virsh -c ${LIBVIRT_URI}"

if ! $VIRSH dominfo "$VM_NAME" &>/dev/null; then
  echo "ERROR: libvirt VM '${VM_NAME}' not found. Create nested Proxmox first."
  exit 1
fi

STATE=$($VIRSH domstate "$VM_NAME" 2>/dev/null || echo unknown)
if [[ "$STATE" != "running" ]]; then
  echo "Starting ${VM_NAME} (was: ${STATE})..."
  $VIRSH start "$VM_NAME"
  echo "Waiting for nested Proxmox to boot..."
  sleep 45
fi

IP=$($VIRSH domifaddr "$VM_NAME" 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d/ -f1 | head -1)
if [[ -n "$IP" ]]; then
  echo "Nested Proxmox IP: ${IP} — GUI https://${IP}:8006"
else
  echo "WARN: no IP yet for ${VM_NAME}; check: virsh domifaddr ${VM_NAME}"
fi
