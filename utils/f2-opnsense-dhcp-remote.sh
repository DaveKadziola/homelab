#!/usr/bin/env sh
# Run ON OPNsense as root (piped via SSH). Fixes the IOT DHCP static maps for F3/F5 (2026-10-19):
#   .20.20 pointed at 7c:d3:0a:1a:f5:10, which is not on the Proxmox PC (its NICs: 70:85:c2:53:e0:ac,
#   3c:49:37:19:71:ae/af) - by elimination the HP t620. So .20.20 -> Proxmox nic1 3c:49:37:19:71:ae,
#   and 7c:d3:0a:1a:f5:10 -> .20.13 (Home Assistant).
# Idempotent. Pre-change backup, automatic revert after REVERT_AFTER seconds unless
# /tmp/homelab-dhcp-keep appears. --dry-run via DRY_RUN=1. Do not store secrets in this file.

set -eu

CONFIG=/conf/config.xml
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="/conf/config.xml.homelab-v2-${STAMP}"
KEEP=/tmp/homelab-dhcp-keep
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN="${DRY_RUN:-0}"

[ "$DRY_RUN" = 1 ] || { cp "$CONFIG" "$BACKUP"; echo "Backup on router: $BACKUP"; }

DRY_RUN="$DRY_RUN" python3 <<'PY'
import os, sys
import xml.etree.ElementTree as ET

CONFIG = "/conf/config.xml"
T620 = "7c:d3:0a:1a:f5:10"
PVE = "3c:49:37:19:71:ae"
dry = os.environ.get("DRY_RUN") == "1"

tree = ET.parse(CONFIG)
dh = tree.getroot().find("./dhcpd/opt3")
if dh is None:
    sys.exit("ERROR: no IOT (opt3) DHCP server, stop")
maps = {m.findtext("ipaddr"): m for m in dh.findall("staticmap")}
changed = False

pve = maps.get("192.168.20.20")
if pve is None:
    sys.exit("ERROR: no static map for 192.168.20.20, stop")
if pve.findtext("mac") == T620:
    print(f".20.20: {T620} -> {PVE} (proxmox nic1)")
    pve.find("mac").text = PVE
    changed = True
elif pve.findtext("mac") == PVE:
    print(".20.20 already on the Proxmox nic1 - skip")
else:
    sys.exit(f"ERROR: .20.20 has unexpected MAC {pve.findtext('mac')}, stop")

if any(m.findtext("mac") == T620 for m in dh.findall("staticmap")):
    print(f"{T620} already mapped - skip")
elif "192.168.20.13" in maps:
    sys.exit("ERROR: 192.168.20.13 is mapped to another MAC, stop")
else:
    new = ET.fromstring(ET.tostring(pve))  # same fields as an existing map; the rest are empty
    new.find("mac").text = T620
    new.find("ipaddr").text = "192.168.20.13"
    new.find("hostname").text = "homeassistant"
    new.find("descr").text = "HP t620 Home Assistant"
    dh.insert(list(dh).index(pve), new)
    print(f"add {T620} -> 192.168.20.13 (homeassistant)")
    changed = True

if changed and not dry:
    tree.write(CONFIG, encoding="UTF-8", xml_declaration=True)
    print("config written")
open("/tmp/homelab-dhcp-changed", "w").write("1" if changed else "0")
PY

[ "$DRY_RUN" = 1 ] && { echo "dry run - nothing written"; exit 0; }
[ "$(cat /tmp/homelab-dhcp-changed)" = 1 ] || { rm -f "$BACKUP"; echo "nothing to change"; exit 0; }

rm -f "$KEEP"
/usr/local/sbin/configctl dhcpd restart
echo "dhcpd restarted"
grep -A3 -E "3c:49:37:19:71:ae|7c:d3:0a:1a:f5:10" /var/dhcpd/etc/dhcpd.conf | grep -E "hardware|fixed-address"
daemon -f -P /tmp/homelab-dhcp-revert.pid sh -c "sleep ${REVERT_AFTER}; [ -f ${KEEP} ] || { cp ${BACKUP} ${CONFIG}; /usr/local/sbin/configctl dhcpd restart; echo reverted > /tmp/homelab-dhcp-reverted; }"
echo "auto-revert armed: ${REVERT_AFTER}s, cancel with: touch ${KEEP}"
echo "manual revert: cp ${BACKUP} ${CONFIG} && configctl dhcpd restart"
