#!/usr/bin/env sh
# Run ON OPNsense as root (piped via SSH). Closes the IOT allow-all (audit 2026-10-19):
#   - disables the IOT "pass any -> any" rule that made the NotForIOT block a no-op;
#   - points the IOT DNS rule at the IOT address instead of the HOME OFFICE one.
# Idempotent. Pre-change backup, and an automatic revert after REVERT_AFTER seconds unless
# /tmp/homelab-iot-keep appears (created by f2-opnsense-iot.sh once the checks pass).
# --dry-run prints what would change and touches nothing. Do not store secrets in this file.

set -eu

CONFIG=/conf/config.xml
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="/conf/config.xml.homelab-v2-${STAMP}"
KEEP=/tmp/homelab-iot-keep
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN="${DRY_RUN:-0}"

[ "$DRY_RUN" = 1 ] || { cp "$CONFIG" "$BACKUP"; echo "Backup on router: $BACKUP"; }

DRY_RUN="$DRY_RUN" python3 <<'PY'
import os, sys
import xml.etree.ElementTree as ET

CONFIG = "/conf/config.xml"
ALLOW_ALL = "6d84aee1-8215-404e-b6db-a047543e1f83"   # opt3 pass any -> any, no descr
DNS_RULE = "21d6e435-dba8-4a82-8428-4208468f551f"    # "Allow IOT access to DNS"
dry = os.environ.get("DRY_RUN") == "1"

tree = ET.parse(CONFIG)
rules = {r.get("uuid"): r for r in tree.getroot().findall("./filter/rule")}
changed = False

r = rules.get(ALLOW_ALL)
if r is None or r.findtext("interface") != "opt3":
    sys.exit("ERROR: IOT allow-all rule not found by uuid - config differs from the audit, stop")
if r.find("disabled") is None:
    print("disable: opt3 pass any -> any")
    ET.SubElement(r, "disabled").text = "1"
    changed = True
else:
    print("allow-all already disabled - skip")

r = rules.get(DNS_RULE)
if r is None or r.findtext("interface") != "opt3":
    sys.exit("ERROR: IOT DNS rule not found by uuid - config differs from the audit, stop")
net = r.find("./destination/network")
if net is not None and net.text == "opt2ip":
    print("DNS rule: destination opt2ip -> opt3ip")
    net.text = "opt3ip"
    changed = True
else:
    print("DNS rule destination is %s - skip" % (net.text if net is not None else "?"))

if changed and not dry:
    tree.write(CONFIG, encoding="UTF-8", xml_declaration=True)
    print("config written")
open("/tmp/homelab-iot-changed", "w").write("1" if changed else "0")
PY

[ "$DRY_RUN" = 1 ] && { echo "dry run - nothing written"; exit 0; }
[ "$(cat /tmp/homelab-iot-changed)" = 1 ] || { rm -f "$BACKUP"; echo "nothing to change"; exit 0; }

rm -f "$KEEP"
/usr/local/sbin/configctl filter reload
echo "filter reload OK"
# Dead-man switch: restore the backup unless the laptop confirms the checks passed.
daemon -f sh -c "sleep ${REVERT_AFTER}; [ -f ${KEEP} ] || { cp ${BACKUP} ${CONFIG}; /usr/local/sbin/configctl filter reload; echo reverted > /tmp/homelab-iot-reverted; }"
echo "auto-revert armed: ${REVERT_AFTER}s, cancel with: touch ${KEEP}"
echo "manual revert: cp ${BACKUP} ${CONFIG} && configctl filter reload"
