#!/usr/bin/env sh
# Run ON OPNsense as root (piped via SSH). Moves DMZ (opt5, vlan06) out of the APP /26 (audit 2026-10-19):
#   192.168.50.1/28 (.0-.15, inside APP 192.168.50.0/26) -> 192.168.50.65/28 (.64-.79).
# Also drops what pointed at the dead NPM 192.168.50.2: its DHCP static map, and disables the LAN
# "NPM administration" and DMZ "app servers" rules and its WAN port-forward (MVC rule, <disabled>0|1</disabled>).
# Idempotent. Pre-change backup, automatic revert after REVERT_AFTER seconds unless
# /tmp/homelab-dmz-keep appears. --dry-run via DRY_RUN=1. Do not store secrets in this file.

set -eu

CONFIG=/conf/config.xml
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="/conf/config.xml.homelab-v2-${STAMP}"
KEEP=/tmp/homelab-dmz-keep
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN="${DRY_RUN:-0}"

[ "$DRY_RUN" = 1 ] || { cp "$CONFIG" "$BACKUP"; echo "Backup on router: $BACKUP"; }

DRY_RUN="$DRY_RUN" python3 <<'PY'
import os, sys
import xml.etree.ElementTree as ET

CONFIG = "/conf/config.xml"
OLD_IP, NEW_IP, BITS = "192.168.50.1", "192.168.50.65", "28"
NPM = "192.168.50.2"
RULES = {"f6276c97-27eb-4b5b-97c7-f97974884bc6": "lan", "c6892fa1-201c-4687-8967-45f4358e3f30": "opt5"}
dry = os.environ.get("DRY_RUN") == "1"

tree = ET.parse(CONFIG)
root = tree.getroot()
changed = False

iface = root.find("./interfaces/opt5")
if iface is None or iface.findtext("if") != "vlan06":
    sys.exit("ERROR: opt5 is not vlan06 - config differs from the audit, stop")
ip = iface.find("ipaddr")
if ip.text == OLD_IP:
    if iface.findtext("subnet") != BITS:
        sys.exit("ERROR: opt5 subnet is not /28, stop")
    print(f"opt5: {OLD_IP}/{BITS} -> {NEW_IP}/{BITS}")
    ip.text = NEW_IP
    changed = True
elif ip.text == NEW_IP:
    print("opt5 already renumbered - skip")
else:
    sys.exit(f"ERROR: opt5 has unexpected address {ip.text}, stop")

dh = root.find("./dhcpd/opt5")
if dh is not None:
    rng = dh.find("range")
    if rng is not None and rng.findtext("from") == "192.168.50.7":
        print("opt5 DHCP range (disabled): .7-.14 -> .71-.78")
        rng.find("from").text, rng.find("to").text = "192.168.50.71", "192.168.50.78"
        changed = True
    for m in dh.findall("staticmap"):
        if m.findtext("ipaddr") == NPM:
            print("remove DHCP static map", NPM, m.findtext("descr"))
            dh.remove(m)
            changed = True

rules = {r.get("uuid"): r for r in root.findall("./filter/rule")}
for uuid, ifname in RULES.items():
    r = rules.get(uuid)
    if r is None or r.findtext("interface") != ifname:
        sys.exit(f"ERROR: rule {uuid} not found on {ifname}, stop")
    if r.find("disabled") is None:
        print("disable rule:", r.findtext("descr"))
        ET.SubElement(r, "disabled").text = "1"
        changed = True

NPM_RDR = "5e3c49fc-1bb3-456c-b781-c3b9e9d1e696"
n = next((r for r in root.findall("./nat/rule") if r.get("uuid") == NPM_RDR), None)
if n is None or n.findtext("target") != NPM:
    sys.exit("ERROR: NPM port-forward not found as audited, stop")
if n.findtext("disabled") != "1":
    print("disable WAN port-forward to", NPM)
    n.find("disabled").text = "1"
    changed = True

if changed and not dry:
    tree.write(CONFIG, encoding="UTF-8", xml_declaration=True)
    print("config written")
open("/tmp/homelab-dmz-changed", "w").write("1" if changed else "0")
PY

[ "$DRY_RUN" = 1 ] && { echo "dry run - nothing written"; exit 0; }
[ "$(cat /tmp/homelab-dmz-changed)" = 1 ] || { rm -f "$BACKUP"; echo "nothing to change"; exit 0; }

rm -f "$KEEP"
/usr/local/sbin/configctl interface reconfigure opt5
/usr/local/sbin/configctl filter reload
echo "opt5 reconfigured, filter reloaded"
daemon -f -P /tmp/homelab-dmz-revert.pid sh -c "sleep ${REVERT_AFTER}; [ -f ${KEEP} ] || { cp ${BACKUP} ${CONFIG}; /usr/local/sbin/configctl interface reconfigure opt5; /usr/local/sbin/configctl filter reload; echo reverted > /tmp/homelab-dmz-reverted; }"
echo "auto-revert armed: ${REVERT_AFTER}s, cancel with: touch ${KEEP}"
echo "manual revert: cp ${BACKUP} ${CONFIG} && configctl interface reconfigure opt5 && configctl filter reload"
ifconfig vlan06 | grep "inet "
ifconfig qinq01 | grep "inet "
