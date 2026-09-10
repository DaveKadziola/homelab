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
if [[ "$STATE" != "running" && "$STATE" != "uruchomiona" ]]; then
  echo "Starting ${VM_NAME} (was: ${STATE})..."
  $VIRSH start "$VM_NAME"
  echo "Waiting for nested Proxmox to boot..."
  sleep 30
fi

detect_ip() {
  local ip
  ip=$($VIRSH domifaddr "$VM_NAME" 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d/ -f1 | head -1)
  if [[ -n "$ip" ]]; then
    echo "$ip"
    return 0
  fi
  # Static guest IP may not appear in dnsmasq leases — fall back to ARP/neigh by MAC
  local mac
  mac=$($VIRSH domiflist "$VM_NAME" 2>/dev/null | awk 'NR>2 && $1!=""{print $5; exit}')
  if [[ -n "$mac" ]]; then
    ip=$(ip neigh show | awk -v m="$mac" 'BEGIN{IGNORECASE=1} $0 ~ m && $1 ~ /^192\.168\.122\./ {print $1; exit}')
    if [[ -n "$ip" ]]; then
      echo "$ip"
      return 0
    fi
  fi
  # Known as-built static (legacy)
  if curl -fsSk --max-time 2 -o /dev/null "https://192.168.122.219:8006/" 2>/dev/null; then
    echo "192.168.122.219"
    return 0
  fi
  return 1
}

IP=""
for _ in $(seq 1 24); do
  if IP=$(detect_ip); then
    break
  fi
  sleep 5
done

if [[ -n "${IP:-}" ]]; then
  echo "Nested Proxmox IP: ${IP} — GUI https://${IP}:8006"
  if curl -fsSk --max-time 5 -o /dev/null "https://${IP}:8006/" 2>/dev/null; then
    echo "OK HTTPS :8006"
  else
    echo "WARN :8006 not responding yet"
  fi
else
  echo "WARN: no IP yet for ${VM_NAME}; check: virsh -c ${LIBVIRT_URI} domifaddr ${VM_NAME}"
fi
