#!/usr/bin/env sh
# Run ON OPNsense as root (piped via SSH). APP (opt6) reaches the NAS over NFS and the internet only
# on the ports the apps use: TCP 80, 443, 587 (mail), 22000 and 22067 (Syncthing), UDP 123 and
# 22000, and ping; the rest is blocked and logged. The ports come from the pf states of 2026-10-24
# and the services in compose/core. Removes the unused APP .50.30 -> NAS SSH rule (audit S25).
# DNS to the router is passed by the CommonDNS group rule to (self):53. Idempotent: rules are found
# by descr and replaced when they differ. Pre-change backup, automatic revert after REVERT_AFTER
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
import os, sys, uuid
import xml.etree.ElementTree as ET

CONFIG = "/conf/config.xml"
MARK = "homelab-v2 APP to the internet"
STALE_SSH = "homelab-v2 SSH ubuntu-apps to NAS TCP 22"
dry = os.environ.get("DRY_RUN") == "1"
tree = ET.parse(CONFIG)
root = tree.getroot()
filt = root.find("filter")
changes = []


def rule(typ, descr, proto=None, port=None, icmptype=None, log=False, dst_any=False):
    r = ET.Element("rule", uuid=str(uuid.uuid4()))
    for tag, val in (("type", typ), ("interface", "opt6"), ("ipprotocol", "inet"),
                     ("statetype", "keep state"), ("descr", descr), ("direction", "in"), ("quick", "1")):
        ET.SubElement(r, tag).text = val
    if proto:
        ET.SubElement(r, "protocol").text = proto
    if icmptype:
        ET.SubElement(r, "icmptype").text = icmptype
    if log:
        ET.SubElement(r, "log").text = "1"
    src = ET.SubElement(r, "source")
    ET.SubElement(src, "network").text = "opt6"
    dst = ET.SubElement(r, "destination")
    if dst_any:
        ET.SubElement(dst, "any").text = "1"
    else:
        ET.SubElement(dst, "address").text = "PrivateNetworks"
        if port:
            ET.SubElement(dst, "port").text = port
        ET.SubElement(dst, "not").text = "1"
    return r


def shape(e):
    return "".join(ET.tostring(c, encoding="unicode").strip() for c in e if c.tag not in ("created", "updated"))


def ensure_alias(name, content, description):
    aliases = root.find(".//OPNsense/Firewall/Alias/aliases")
    text = "\n".join(content)
    old = next((a for a in aliases.findall("alias") if a.findtext("name") == name), None)
    if old is not None:
        if old.findtext("content") != text:
            old.find("content").text = text
            changes.append(f"update alias {name}: {', '.join(content)}")
        return
    a = ET.SubElement(aliases, "alias", uuid=str(uuid.uuid4()))
    for tag, val in (("enabled", "1"), ("name", name), ("type", "port"), ("path_expression", None),
                     ("proto", None), ("interface", None), ("counters", "0"), ("updatefreq", None),
                     ("content", text), ("password", None), ("username", None), ("authtype", None),
                     ("categories", None), ("description", description)):
        ET.SubElement(a, tag).text = val
    changes.append(f"add alias {name}: {', '.join(content)}")


ensure_alias("AppEgressTcp", ["80", "443", "587", "22000", "22067"], "homelab-v2: APP to the internet, TCP")
ensure_alias("AppEgressUdp", ["123", "22000"], "homelab-v2: APP to the internet, UDP")

rules = filt.findall("rule")
app = [r for r in rules if r.findtext("interface") == "opt6"]
if not app:
    sys.exit("ERROR: no APP rules found, stop")
stale = next((r for r in rules if r.findtext("descr") == STALE_SSH), None)
if stale is not None:
    filt.remove(stale)
    changes.append(f"remove rule: {STALE_SSH}")

# The broad rule keeps its descr and position and becomes the TCP one.
want = [rule("pass", MARK, "tcp", "AppEgressTcp"),
        rule("pass", "homelab-v2 APP to the internet UDP", "udp", "AppEgressUdp"),
        rule("pass", "homelab-v2 APP ping the internet", "icmp", icmptype="echoreq"),
        rule("block", "homelab-v2 APP block the rest", log=True, dst_any=True)]
anchor = next((r for r in filt.findall("rule") if r.findtext("descr") == MARK), None)
pos = list(filt).index(anchor) if anchor is not None else list(filt).index(app[-1]) + 1
for new in want:
    old = next((r for r in filt.findall("rule") if r.findtext("descr") == new.findtext("descr")), None)
    if old is not None:
        pos = list(filt).index(old)
        if shape(old) != shape(new):
            new.set("uuid", old.get("uuid") or new.get("uuid"))
            filt.remove(old)
            filt.insert(pos, new)
            changes.append(f"update rule: {new.findtext('descr')}")
    else:
        filt.insert(pos, new)
        changes.append(f"add rule: {new.findtext('descr')}")
    pos += 1

for c in changes:
    print(("would " if dry else "") + c)
if changes and not dry:
    tree.write(CONFIG, encoding="UTF-8", xml_declaration=True)
    print("config written")
open("/tmp/homelab-appfw-changed", "w").write("1" if changes else "0")
PY

[ "$DRY_RUN" = 1 ] && { echo "dry run - nothing written"; exit 0; }
[ "$(cat /tmp/homelab-appfw-changed)" = 1 ] || { rm -f "$BACKUP"; echo "nothing to change"; exit 0; }

rm -f "$KEEP"
/usr/local/sbin/configctl filter reload
echo "filter reload OK"
daemon -f -P /tmp/homelab-appfw-revert.pid sh -c "sleep ${REVERT_AFTER}; [ -f ${KEEP} ] || { cp ${BACKUP} ${CONFIG}; /usr/local/sbin/configctl filter reload; echo reverted > /tmp/homelab-appfw-reverted; }"
echo "auto-revert armed: ${REVERT_AFTER}s, cancel with: touch ${KEEP}"
echo "manual revert: cp ${BACKUP} ${CONFIG} && configctl filter reload"
