#!/usr/bin/env sh
# Run ON OPNsense as root (piped via SSH). APP (opt6) had only the NFS-to-NAS rules, so ubuntu-apps
# could not reach the internet (images, apt, GitHub runner, rclone). Adds one rule, modelled on the
# GUEST one: APP net -> !PrivateNetworks. DNS to the router is already passed by the CommonDNS
# group rule to (self):53. Idempotent. Pre-change backup, automatic revert after REVERT_AFTER
# seconds unless /tmp/homelab-appfw-keep appears. --dry-run via DRY_RUN=1. No secrets here.

set -eu

CONFIG=/conf/config.xml
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="/conf/config.xml.homelab-v2-${STAMP}"
KEEP=/tmp/homelab-appfw-keep
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN="${DRY_RUN:-0}"

[ "$DRY_RUN" = 1 ] || { cp "$CONFIG" "$BACKUP"; echo "Backup on router: $BACKUP"; }

DRY_RUN="$DRY_RUN" python3 <<'PY'
import copy, os, sys, uuid
import xml.etree.ElementTree as ET

CONFIG = "/conf/config.xml"
MARK = "homelab-v2 APP to the internet"
GUEST = "a36afa31-f190-43f5-ade0-7ae1b7de6537"
dry = os.environ.get("DRY_RUN") == "1"
tree = ET.parse(CONFIG)
filt = tree.getroot().find("filter")
rules = filt.findall("rule")
changed = False

if any(r.findtext("descr") == MARK for r in rules):
    print("APP internet rule present - skip")
else:
    base = next((r for r in rules if r.get("uuid") == GUEST), None)
    if base is None or base.findtext("destination/address") != "PrivateNetworks":
        sys.exit("ERROR: GUEST internet rule not found as audited, stop")
    nfs = [r for r in rules if r.findtext("interface") == "opt6"]
    if not nfs:
        sys.exit("ERROR: no APP rules found, stop")
    new = copy.deepcopy(base)
    new.set("uuid", str(uuid.uuid4()))
    for t in ("created", "updated"):
        e = new.find(t)
        if e is not None: new.remove(e)
    new.find("interface").text = "opt6"
    src = new.find("source")
    for c in list(src): src.remove(c)
    ET.SubElement(src, "network").text = "opt6"
    new.find("descr").text = MARK
    filt.insert(list(filt).index(nfs[-1]) + 1, new)
    print("add opt6: APP net -> !PrivateNetworks (internet)")
    changed = True

if changed and not dry:
    tree.write(CONFIG, encoding="UTF-8", xml_declaration=True)
    print("config written")
open("/tmp/homelab-appfw-changed", "w").write("1" if changed else "0")
PY

[ "$DRY_RUN" = 1 ] && { echo "dry run - nothing written"; exit 0; }
[ "$(cat /tmp/homelab-appfw-changed)" = 1 ] || { rm -f "$BACKUP"; echo "nothing to change"; exit 0; }

rm -f "$KEEP"
/usr/local/sbin/configctl filter reload
echo "filter reload OK"
daemon -f -P /tmp/homelab-appfw-revert.pid sh -c "sleep ${REVERT_AFTER}; [ -f ${KEEP} ] || { cp ${BACKUP} ${CONFIG}; /usr/local/sbin/configctl filter reload; echo reverted > /tmp/homelab-appfw-reverted; }"
echo "auto-revert armed: ${REVERT_AFTER}s, cancel with: touch ${KEEP}"
echo "manual revert: cp ${BACKUP} ${CONFIG} && configctl filter reload"
