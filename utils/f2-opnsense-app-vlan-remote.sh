#!/usr/bin/env sh
# Run ON OPNsense as root (piped via SSH). APP from QinQ (tag 51 inside VLAN 50, qinq01) to a plain
# VLAN 51 on the igc2 trunk (vlan07), 2026-10-19: the NETGEAR GS308EP does not carry the QinQ, and
# the Proxmox nic2 port gets VLAN 51 tagged. opt6 keeps 192.168.50.50/26.
# Idempotent. Pre-change backup, automatic revert after REVERT_AFTER seconds unless
# /tmp/homelab-app-keep appears. --dry-run via DRY_RUN=1. Do not store secrets in this file.

set -eu

CONFIG=/conf/config.xml
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="/conf/config.xml.homelab-v2-${STAMP}"
KEEP=/tmp/homelab-app-keep
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN="${DRY_RUN:-0}"

[ "$DRY_RUN" = 1 ] || { cp "$CONFIG" "$BACKUP"; echo "Backup on router: $BACKUP"; }

DRY_RUN="$DRY_RUN" python3 <<'PY'
import copy, os, sys, uuid
import xml.etree.ElementTree as ET

CONFIG = "/conf/config.xml"
dry = os.environ.get("DRY_RUN") == "1"
tree = ET.parse(CONFIG)
root = tree.getroot()
vlans = root.find("vlans")
opt6 = root.find("./interfaces/opt6")
by_if = {v.findtext("vlanif"): v for v in vlans.findall("vlan")}
changed = False

if opt6.findtext("if") == "vlan07" and "vlan07" in by_if:
    print("APP already on vlan07 - skip")
else:
    if opt6.findtext("if") != "qinq01" or opt6.findtext("ipaddr") != "192.168.50.50":
        sys.exit("ERROR: opt6 is not APP on qinq01 as audited, stop")
    if "vlan07" in by_if:
        sys.exit("ERROR: vlan07 already exists for something else, stop")
    old = by_if["qinq01"]
    new = copy.deepcopy(old)
    new.set("uuid", str(uuid.uuid4()))
    new.find("if").text = "igc2"
    new.find("vlanif").text = "vlan07"
    vlans.insert(list(vlans).index(old), new)
    vlans.remove(old)
    opt6.find("if").text = "vlan07"
    print("APP: qinq01 (vlan06 tag 51) -> vlan07 (igc2 tag 51), opt6 if -> vlan07")
    changed = True

if changed and not dry:
    tree.write(CONFIG, encoding="UTF-8", xml_declaration=True)
    print("config written")
open("/tmp/homelab-app-changed", "w").write("1" if changed else "0")
PY

[ "$DRY_RUN" = 1 ] && { echo "dry run - nothing written"; exit 0; }
[ "$(cat /tmp/homelab-app-changed)" = 1 ] || { rm -f "$BACKUP"; echo "nothing to change"; exit 0; }

rm -f "$KEEP"
# reconfigure_vlans.php destroys a vlan device only when it is listed here (the UI does that on delete)
apply() { echo qinq01 >> /tmp/.vlans.removed; /usr/local/sbin/configctl interface vlan configure; /usr/local/sbin/configctl interface reconfigure opt6; /usr/local/sbin/configctl filter reload; }
apply
echo "vlans reconfigured, opt6 reconfigured, filter reloaded"
ifconfig vlan07 2>/dev/null | grep -E "inet |vlan:" || echo "vlan07 missing"
ifconfig qinq01 >/dev/null 2>&1 && echo "qinq01 still present" || echo "qinq01 gone"
daemon -f -P /tmp/homelab-app-revert.pid sh -c "sleep ${REVERT_AFTER}; [ -f ${KEEP} ] || { cp ${BACKUP} ${CONFIG}; echo vlan07 >> /tmp/.vlans.removed; /usr/local/sbin/configctl interface vlan configure; /usr/local/sbin/configctl interface reconfigure opt6; /usr/local/sbin/configctl filter reload; echo reverted > /tmp/homelab-app-reverted; }"
echo "auto-revert armed: ${REVERT_AFTER}s, cancel with: touch ${KEEP}"
echo "manual revert: cp ${BACKUP} ${CONFIG} && echo vlan07 >> /tmp/.vlans.removed && configctl interface vlan configure && configctl interface reconfigure opt6 && configctl filter reload"
