#!/usr/bin/env sh
# Run ON OPNsense as root (piped via SSH). The public Grocery backend pointed at
# 192.168.50.30:8080, which is Dozzle (container logs) in compose; Grocery listens on 8101
# (config/services.yml). Found 2026-10-19 before ubuntu-apps existed. Sets the port, regenerates
# haproxy.conf, tests it, reloads. Idempotent; backup + auto-revert unless /tmp/homelab-haproxy-keep.
# --dry-run via DRY_RUN=1. Do not store secrets in this file.

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
SERVER = "d6ddeb0e-482d-46ef-9745-a7fe08ad31a4"  # grocery-app
dry = os.environ.get("DRY_RUN") == "1"
tree = ET.parse(CONFIG)
s = next((x for x in tree.getroot().findall("./OPNsense/HAProxy/servers/server") if x.get("uuid") == SERVER), None)
if s is None or s.findtext("name") != "grocery-app" or s.findtext("address") != "192.168.50.30":
    sys.exit("ERROR: grocery-app server not found as audited, stop")
changed = False
if s.findtext("port") == "8101":
    print("grocery-app already on 8101 - skip")
else:
    print(f"grocery-app port {s.findtext('port')} -> 8101")
    s.find("port").text = "8101"
    changed = True
if changed and not dry:
    tree.write(CONFIG, encoding="UTF-8", xml_declaration=True)
    print("config written")
open("/tmp/homelab-haproxy-changed", "w").write("1" if changed else "0")
PY

[ "$DRY_RUN" = 1 ] && { echo "dry run - nothing written"; exit 0; }
[ "$(cat /tmp/homelab-haproxy-changed)" = 1 ] || { rm -f "$BACKUP"; echo "nothing to change"; exit 0; }

rm -f "$KEEP"
# The template writes haproxy.conf.staging; "configctl haproxy configtest" always exits 0, so test
# the staging file directly (after its setup step) before "reload" deploys it.
/usr/local/sbin/configctl template reload OPNsense/HAProxy >/dev/null
/usr/local/sbin/configctl haproxy configtest >/dev/null
if ! /usr/local/sbin/haproxy -c -f /usr/local/etc/haproxy.conf.staging >/dev/null 2>&1 \
   || ! grep -q "server grocery-app 192.168.50.30:8101" /usr/local/etc/haproxy.conf.staging; then
  cp "$BACKUP" "$CONFIG"; /usr/local/sbin/configctl template reload OPNsense/HAProxy >/dev/null
  echo "staging config invalid - restored"; exit 1
fi
/usr/local/sbin/configctl haproxy reload
echo "haproxy reloaded"
grep -n "server grocery-app" /usr/local/etc/haproxy.conf
daemon -f -P /tmp/homelab-haproxy-revert.pid sh -c "sleep ${REVERT_AFTER}; [ -f ${KEEP} ] || { cp ${BACKUP} ${CONFIG}; /usr/local/sbin/configctl template reload OPNsense/HAProxy; /usr/local/sbin/configctl haproxy reload; echo reverted > /tmp/homelab-haproxy-reverted; }"
echo "auto-revert armed: ${REVERT_AFTER}s, cancel with: touch ${KEEP}"
echo "manual revert: cp ${BACKUP} ${CONFIG} && configctl template reload OPNsense/HAProxy && configctl haproxy reload"
