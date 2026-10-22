#!/usr/bin/env sh
# Run ON OPNsense as root (piped via SSH). The two APP -> NAS NFS rules carried their port in a
# top-level <destinationport>, which pf ignores: they passed every TCP port from APP to
# 192.168.20.12 (pfctl -sr, 2026-10-19). Moves the port into <destination><port> and adds SSH 22
# from ubuntu-apps only (the prod runner deploys the NAS with Ansible).
# Idempotent. Pre-change backup, automatic revert after REVERT_AFTER seconds unless
# /tmp/homelab-nasports-keep appears. --dry-run via DRY_RUN=1. Do not store secrets in this file.

set -eu

CONFIG=/conf/config.xml
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="/conf/config.xml.homelab-v2-${STAMP}"
KEEP=/tmp/homelab-nasports-keep
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN="${DRY_RUN:-0}"

[ "$DRY_RUN" = 1 ] || { cp "$CONFIG" "$BACKUP"; echo "Backup on router: $BACKUP"; }

DRY_RUN="$DRY_RUN" python3 <<'PY'
import copy, os, sys
import xml.etree.ElementTree as ET

CONFIG = "/conf/config.xml"
NAS = "192.168.20.12/32"
SSH_DESCR = "homelab-v2 SSH ubuntu-apps to NAS TCP 22"
dry = os.environ.get("DRY_RUN") == "1"
tree = ET.parse(CONFIG)
filt = tree.getroot().find("filter")
rules = filt.findall("rule")
nfs = [r for r in rules if (r.findtext("descr") or "").startswith("homelab-v2 NFS APP to NAS TCP ")]
if len(nfs) != 2 or any(r.findtext("interface") != "opt6" or r.findtext("destination/address") != NAS for r in nfs):
    sys.exit("ERROR: the two APP -> NAS NFS rules are not as audited, stop")
changed = False

for r in nfs:
    want = r.findtext("descr").rsplit(" ", 1)[1]
    loose = r.find("destinationport")
    dst = r.find("destination")
    if dst.findtext("port") == want and loose is None:
        print(f"NFS {want}: port already in destination - skip")
        continue
    if loose is not None:
        r.remove(loose)
    p = dst.find("port")
    if p is None:
        p = ET.SubElement(dst, "port")
    p.text = want
    print(f"NFS {want}: destination port set, top-level destinationport removed")
    changed = True

if any(r.findtext("descr") == SSH_DESCR for r in rules):
    print("SSH rule present - skip")
else:
    ssh = copy.deepcopy(nfs[0])
    ssh.find("descr").text = SSH_DESCR
    src = ssh.find("source")
    for c in list(src):
        src.remove(c)
    ET.SubElement(src, "address").text = "192.168.50.30/32"
    ssh.find("destination/port").text = "22"
    filt.insert(list(filt).index(nfs[-1]) + 1, ssh)
    print("add: 192.168.50.30 -> NAS TCP 22")
    changed = True

if changed and not dry:
    tree.write(CONFIG, encoding="UTF-8", xml_declaration=True)
    print("config written")
open("/tmp/homelab-nasports-changed", "w").write("1" if changed else "0")
PY

[ "$DRY_RUN" = 1 ] && { echo "dry run - nothing written"; exit 0; }
[ "$(cat /tmp/homelab-nasports-changed)" = 1 ] || { rm -f "$BACKUP"; echo "nothing to change"; exit 0; }

rm -f "$KEEP"
/usr/local/sbin/configctl filter reload
echo "filter reload OK"
pfctl -sr | grep "192.168.20.12"
daemon -f -P /tmp/homelab-nasports-revert.pid sh -c "sleep ${REVERT_AFTER}; [ -f ${KEEP} ] || { cp ${BACKUP} ${CONFIG}; /usr/local/sbin/configctl filter reload; echo reverted > /tmp/homelab-nasports-reverted; }"
echo "auto-revert armed: ${REVERT_AFTER}s, cancel with: touch ${KEEP}"
echo "manual revert: cp ${BACKUP} ${CONFIG} && configctl filter reload"
