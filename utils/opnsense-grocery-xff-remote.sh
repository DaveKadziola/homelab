#!/usr/bin/env sh
# Run ON OPNsense as root (piped via SSH). The public Grocery backend sent no X-Forwarded-For or
# X-Forwarded-Proto, so EasyToDo saw every public client as the router (shared per-IP rate limits).
# Turns on "X-Forwarded-For header" and sets X-Forwarded-Proto on backend "grocery" only,
# regenerates haproxy.conf, tests it, reloads. Idempotent; backup + auto-revert unless
# /tmp/homelab-haproxy-keep. --dry-run via DRY_RUN=1. Do not store secrets in this file.

set -eu

CONFIG=/conf/config.xml
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="/conf/config.xml.homelab-v2-${STAMP}"
KEEP=/tmp/homelab-haproxy-keep
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN="${DRY_RUN:-0}"

[ "$DRY_RUN" = 1 ] || { cp "$CONFIG" "$BACKUP"; echo "Backup on router: $BACKUP"; }

DRY_RUN="$DRY_RUN" python3 <<'PY'
import os, sys
import xml.etree.ElementTree as ET

CONFIG = "/conf/config.xml"
BACKEND = "cce5f05d-5582-4790-9d6c-633b0f294a8d"  # grocery
SERVER = "d6ddeb0e-482d-46ef-9745-a7fe08ad31a4"  # grocery-app
OPTION = "http-request set-header X-Forwarded-Proto https"
dry = os.environ.get("DRY_RUN") == "1"
tree = ET.parse(CONFIG)
b = next((x for x in tree.getroot().findall("./OPNsense/HAProxy/backends/backend") if x.get("uuid") == BACKEND), None)
if b is None or b.findtext("name") != "grocery" or b.findtext("linkedServers") != SERVER:
    sys.exit("ERROR: backend grocery not found as audited, stop")
custom = b.findtext("customOptions") or ""
if custom not in ("", OPTION):
    sys.exit("ERROR: backend grocery has other custom options, stop")
print(f"before: forwardFor={b.findtext('forwardFor')} customOptions={custom!r}")
changed = False
if b.findtext("forwardFor") != "1":
    b.find("forwardFor").text = "1"
    changed = True
if custom != OPTION:
    b.find("customOptions").text = OPTION
    changed = True
print(f"after:  forwardFor=1 customOptions={OPTION!r}" if changed else "already set - skip")
if changed and not dry:
    tree.write(CONFIG, encoding="UTF-8", xml_declaration=True)
    print("config written")
open("/tmp/homelab-haproxy-changed", "w").write("1" if changed else "0")
PY

[ "$DRY_RUN" = 1 ] && { echo "dry run - nothing written"; exit 0; }
[ "$(cat /tmp/homelab-haproxy-changed)" = 1 ] || { rm -f "$BACKUP"; echo "nothing to change"; exit 0; }

rm -f "$KEEP"
# "configctl haproxy configtest" always exits 0: test the staging file directly before reload.
/usr/local/sbin/configctl template reload OPNsense/HAProxy >/dev/null
/usr/local/sbin/configctl haproxy configtest >/dev/null
if ! /usr/local/sbin/haproxy -c -f /usr/local/etc/haproxy.conf.staging >/dev/null 2>&1 \
   || ! sed -n '/^backend grocery/,/^$/p' /usr/local/etc/haproxy.conf.staging | grep -q "option forwardfor" \
   || ! sed -n '/^backend grocery/,/^$/p' /usr/local/etc/haproxy.conf.staging | grep -q "set-header X-Forwarded-Proto https"; then
  cp "$BACKUP" "$CONFIG"; /usr/local/sbin/configctl template reload OPNsense/HAProxy >/dev/null
  echo "staging config invalid - restored"; exit 1
fi
/usr/local/sbin/configctl haproxy reload
echo "haproxy reloaded"
sed -n '/^backend grocery/,/^$/p' /usr/local/etc/haproxy.conf
daemon -f -P /tmp/homelab-haproxy-revert.pid sh -c "sleep ${REVERT_AFTER}; [ -f ${KEEP} ] || { cp ${BACKUP} ${CONFIG}; /usr/local/sbin/configctl template reload OPNsense/HAProxy; /usr/local/sbin/configctl haproxy reload; echo reverted > /tmp/homelab-haproxy-reverted; }"
echo "auto-revert armed: ${REVERT_AFTER}s, cancel with: touch ${KEEP}"
echo "manual revert: cp ${BACKUP} ${CONFIG} && configctl template reload OPNsense/HAProxy && configctl haproxy reload"
