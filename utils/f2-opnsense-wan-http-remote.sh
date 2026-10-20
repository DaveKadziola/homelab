#!/usr/bin/env sh
# Run ON OPNsense as root (piped via SSH). A WAN rule passed TCP 80 to the firewall itself, where
# AdGuard Home listens on *:80, so its login page answered from the internet (2026-10-20). Nothing
# needs port 80 on WAN: HAProxy serves only 443 and every ACME certificate uses DNS-01. Disables
# that one rule. Idempotent. Pre-change backup, automatic revert after REVERT_AFTER seconds unless
# /tmp/homelab-wanhttp-keep appears. --dry-run via DRY_RUN=1. Do not store secrets in this file.

set -eu

CONFIG=/conf/config.xml
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="/conf/config.xml.homelab-v2-${STAMP}"
KEEP=/tmp/homelab-wanhttp-keep
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN="${DRY_RUN:-0}"

[ "$DRY_RUN" = 1 ] || { cp "$CONFIG" "$BACKUP"; echo "Backup on router: $BACKUP"; }

DRY_RUN="$DRY_RUN" python3 <<'PY'
import os, sys
import xml.etree.ElementTree as ET

CONFIG = "/conf/config.xml"
DESCR = "homelab-v2: off since 2026-10-20 - port 80 reached the AdGuard Home login; ACME uses DNS-01"
dry = os.environ.get("DRY_RUN") == "1"
tree = ET.parse(CONFIG)
rules = tree.getroot().find("filter").findall("rule")
http = [r for r in rules if r.findtext("interface") == "wan" and r.findtext("type") == "pass"
        and r.findtext("protocol") == "tcp" and r.findtext("destination/port") == "80"]
if len(http) != 1:
    sys.exit(f"ERROR: expected one WAN pass rule for TCP 80, found {len(http)} - stop")
r = http[0]
changed = False
if r.find("disabled") is not None:
    print("WAN TCP 80 rule already disabled - skip")
else:
    ET.SubElement(r, "disabled").text = "1"
    d = r.find("descr")
    if d is None:
        d = ET.SubElement(r, "descr")
    d.text = DESCR
    print("WAN TCP 80 rule: disabled")
    changed = True
if changed and not dry:
    tree.write(CONFIG, encoding="UTF-8", xml_declaration=True)
    print("config written")
open("/tmp/homelab-wanhttp-changed", "w").write("1" if changed else "0")
PY

[ "$DRY_RUN" = 1 ] && { echo "dry run - nothing written"; exit 0; }
[ "$(cat /tmp/homelab-wanhttp-changed)" = 1 ] || { rm -f "$BACKUP"; echo "nothing to change"; exit 0; }

rm -f "$KEEP"
/usr/local/sbin/configctl filter reload
echo "filter reload OK"
daemon -f -P /tmp/homelab-wanhttp-revert.pid sh -c "sleep ${REVERT_AFTER}; [ -f ${KEEP} ] || { cp ${BACKUP} ${CONFIG}; /usr/local/sbin/configctl filter reload; echo reverted > /tmp/homelab-wanhttp-reverted; }"
echo "auto-revert armed: ${REVERT_AFTER}s, cancel with: touch ${KEEP}"
echo "manual revert: cp ${BACKUP} ${CONFIG} && configctl filter reload"
