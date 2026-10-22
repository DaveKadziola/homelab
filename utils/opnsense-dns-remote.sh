#!/usr/bin/env sh
# Run ON OPNsense as root (piped via SSH). Makes the CommonDNS redirect work for UDP (audit 2026-10-19).
# AdGuard Home listens on a wildcard socket and answers a redirected UDP query from the address of
# the client's interface, not from the rdr target 127.0.0.1, so pf cannot map the reply back and the
# client drops it (TCP works). Fix: one redirect per CommonDNS interface to that interface's own
# address - the address AdGuard already answers from - plus one group pass rule to (self) port 53.
# The group redirect to 127.0.0.1 is disabled, not deleted. AdGuard itself is not touched.
# Idempotent. Pre-change backup, automatic revert after REVERT_AFTER seconds unless
# /tmp/homelab-dns-keep appears. --dry-run via DRY_RUN=1. Do not store secrets in this file.

set -eu

CONFIG=/conf/config.xml
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="/conf/config.xml.homelab-v2-${STAMP}"
KEEP=/tmp/homelab-dns-keep
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN="${DRY_RUN:-0}"

[ "$DRY_RUN" = 1 ] || { cp "$CONFIG" "$BACKUP"; echo "Backup on router: $BACKUP"; }

DRY_RUN="$DRY_RUN" python3 <<'PY'
import copy, os, sys, uuid
import xml.etree.ElementTree as ET

CONFIG = "/conf/config.xml"
GROUP_RDR = "75519d1a-6b4c-428d-87cf-8897651eb4fa"   # rdr on CommonDNS -> 127.0.0.1:53
GROUP_PASS = "a4d3d06f-3fe0-407e-9cc2-3e2b50b97fc3"  # pass on CommonDNS -> 127.0.0.1:53
MARK = "homelab-v2 DNS redirect"
dry = os.environ.get("DRY_RUN") == "1"

tree = ET.parse(CONFIG)
root = tree.getroot()
nat = root.find("nat")
rdr = next((r for r in nat.findall("rule") if r.get("uuid") == GROUP_RDR), None)
if rdr is None or rdr.findtext("target") != "127.0.0.1":
    sys.exit("ERROR: group DNS redirect not found as audited, stop")
members = (root.findtext("./ifgroups/ifgroupentry[ifname='CommonDNS']/members") or "").split()
members = [m for g in members for m in g.split(",") if m]
ifaces = root.find("interfaces")
changed = False

seq = max(int(r.findtext("sequence") or 0) for r in nat.findall("rule"))
have = {r.findtext("interface") for r in nat.findall("rule") if MARK in (r.findtext("descr") or "")}
for m in members:
    ip = ifaces.findtext(f"{m}/ipaddr") or ""
    if not ip.count(".") == 3:
        sys.exit(f"ERROR: {m} has no static IPv4 ({ip!r}), stop")
    if m in have:
        print(f"redirect on {m} present - skip"); continue
    new = copy.deepcopy(rdr)
    new.set("uuid", str(uuid.uuid4()))
    seq += 1
    new.find("sequence").text = str(seq)
    new.find("disabled").text = "0"
    new.find("interface").text = m
    new.find("target").text = ip
    new.find("descr").text = f"{MARK} on {m} -> {ip}"
    for t in ("created", "updated"):
        e = new.find(t)
        if e is not None: new.remove(e)
    nat.append(new)
    print(f"add redirect on {m}: !CommonDNS:53 -> {ip}:53")
    changed = True

filt = root.find("filter")
if not any(MARK in (r.findtext("descr") or "") for r in filt.findall("rule")):
    base = next((r for r in filt.findall("rule") if r.get("uuid") == GROUP_PASS), None)
    if base is None:
        sys.exit("ERROR: group DNS pass rule not found as audited, stop")
    p = copy.deepcopy(base)
    p.set("uuid", str(uuid.uuid4()))
    for t in ("associated-rule-id", "created", "updated"):
        e = p.find(t)
        if e is not None: p.remove(e)
    d = p.find("destination")
    for c in list(d): d.remove(c)
    ET.SubElement(d, "network").text = "(self)"
    ET.SubElement(d, "port").text = "53"
    p.find("descr").text = f"{MARK}: CommonDNS -> this firewall :53"
    filt.insert(list(filt).index(base) + 1, p)
    print("add group pass: CommonDNS -> (self):53")
    changed = True

if rdr.findtext("disabled") != "1":
    print("disable group redirect -> 127.0.0.1")
    rdr.find("disabled").text = "1"
    changed = True

if changed and not dry:
    tree.write(CONFIG, encoding="UTF-8", xml_declaration=True)
    print("config written")
open("/tmp/homelab-dns-changed", "w").write("1" if changed else "0")
PY

[ "$DRY_RUN" = 1 ] && { echo "dry run - nothing written"; exit 0; }
[ "$(cat /tmp/homelab-dns-changed)" = 1 ] || { rm -f "$BACKUP"; echo "nothing to change"; exit 0; }

rm -f "$KEEP"
/usr/local/sbin/configctl filter reload
echo "filter reload OK"
pfctl -sn | grep "port = domain"
daemon -f -P /tmp/homelab-dns-revert.pid sh -c "sleep ${REVERT_AFTER}; [ -f ${KEEP} ] || { cp ${BACKUP} ${CONFIG}; /usr/local/sbin/configctl filter reload; echo reverted > /tmp/homelab-dns-reverted; }"
echo "auto-revert armed: ${REVERT_AFTER}s, cancel with: touch ${KEEP}"
echo "manual revert: cp ${BACKUP} ${CONFIG} && configctl filter reload"
