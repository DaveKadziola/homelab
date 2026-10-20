#!/usr/bin/env bash
# DEV twin of the T620: Home Assistant OS as a VM in the laptop's libvirt (network `default`).
#
#   ./utils/dev-haos-vm.sh --dry-run   # show what would be done
#   ./utils/dev-haos-vm.sh             # create or start it, wait until HA answers
#   ./utils/dev-haos-vm.sh --undo      # remove the VM, its disk and the DHCP reservation
#
# Same HAOS release as prod (knowledge/apps/homeassistant.md), so the Supervisor, its add-ons and
# backups behave as on the T620. Fixed MAC + DHCP reservation give it the address in
# config/storage.yml (environments.dev.ha_url). The image is checked against the sha256 digest that
# GitHub publishes for the release asset. Idempotent: an existing VM is only started.

set -euo pipefail

NAME="${HAOS_VM_NAME:-home-assistant-dev}"
VERSION="${HAOS_VERSION:-18.3}"
MAC="52:54:00:48:41:13"
IP="192.168.122.60"
DIR="${HAOS_VM_DIR:-$HOME/HomeLab/VMs}"
DISK="$DIR/$NAME.qcow2"
CACHE="$DIR/cache"
ASSET="haos_ova-${VERSION}.qcow2.xz"
URL="https://github.com/home-assistant/operating-system/releases/download/${VERSION}/${ASSET}"
# virsh prints states in the session language ("uruchomiona" on the runner); the checks need English.
VIRSH=(env LC_ALL=C virsh -c qemu:///system)
MODE=apply
case "${1:-}" in --dry-run) MODE=dry ;; --undo) MODE=undo ;; "") ;; *) echo "unknown option: $1" >&2; exit 2 ;; esac

run() { if [[ $MODE == dry ]]; then echo "would: $*"; else "$@"; fi; }
host_xml="<host mac='${MAC}' name='${NAME}' ip='${IP}'/>"
has_lease() { "${VIRSH[@]}" net-dumpxml default | grep -q "mac='${MAC}'"; }

if [[ $MODE == undo ]]; then
  if "${VIRSH[@]}" dominfo "$NAME" >/dev/null 2>&1; then
    "${VIRSH[@]}" destroy "$NAME" 2>/dev/null || true
    "${VIRSH[@]}" undefine "$NAME" --nvram
  fi
  rm -f "$DISK"
  if has_lease; then "${VIRSH[@]}" net-update default delete ip-dhcp-host "$host_xml" --live --config; fi
  echo "removed: VM $NAME, $DISK, DHCP reservation $IP (image cache $CACHE kept)"
  exit 0
fi

if ! "${VIRSH[@]}" dominfo "$NAME" >/dev/null 2>&1; then
  if [[ ! -f "$DISK" ]]; then
    # Room for the image (~3 GB unpacked, grows with HA images and add-ons).
    free_gb=$(df -BG --output=avail "$DIR" 2>/dev/null | tail -1 | tr -dc 0-9)
    [[ ${free_gb:-0} -ge 15 ]] || { echo "STOP: less than 15 GB free in $DIR" >&2; exit 1; }
    run mkdir -p "$CACHE"
    if [[ ! -f "$CACHE/$ASSET" ]]; then
      want=$(gh api "repos/home-assistant/operating-system/releases/tags/${VERSION}" \
        --jq ".assets[] | select(.name==\"${ASSET}\") | .digest" | sed 's/^sha256://')
      [[ -n "$want" ]] || { echo "STOP: no sha256 digest for $ASSET on GitHub" >&2; exit 1; }
      run curl -fL --retry 3 -o "$CACHE/$ASSET.part" "$URL"
      if [[ $MODE == apply ]]; then
        echo "$want  $CACHE/$ASSET.part" | sha256sum -c --quiet || { echo "STOP: checksum mismatch" >&2; exit 1; }
        mv "$CACHE/$ASSET.part" "$CACHE/$ASSET"
      fi
    fi
    if [[ $MODE == apply ]]; then xz -dkc "$CACHE/$ASSET" > "$DISK.part" && mv "$DISK.part" "$DISK"; else echo "would: unpack to $DISK"; fi
  fi
  if ! has_lease; then run "${VIRSH[@]}" net-update default add-last ip-dhcp-host "$host_xml" --live --config; fi
  run virt-install --connect qemu:///system --name "$NAME" --memory 2048 --vcpus 2 \
    --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no \
    --disk "path=$DISK,bus=virtio" --network "network=default,mac=$MAC,model=virtio" \
    --osinfo linux2022 --graphics none --import --noautoconsole --autostart
elif [[ "$("${VIRSH[@]}" domstate "$NAME")" != "running" ]]; then
  run "${VIRSH[@]}" start "$NAME"
fi
[[ $MODE == dry ]] && { echo "dry run - nothing changed"; exit 0; }

# First boot pulls the HA core image; core is up when its API answers 401 without a token (the
# landing page before it only redirects; /api/onboarding is gone once onboarding is done). HAOS 18.3
# serves HA on port 80 (8123 only redirects there), on the T620 as here.
for _ in $(seq 1 90); do
  if [[ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://${IP}/api/")" == 401 ]]; then echo "HA answers on http://${IP}"; exit 0; fi
  sleep 10
done
echo "STOP: HA did not answer on http://${IP} within 15 minutes (virsh console $NAME)" >&2
exit 1
