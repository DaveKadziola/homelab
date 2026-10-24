#!/usr/bin/env sh
# Run ON OPNsense as root (piped via SSH by utils/opnsense-lockdown.sh). One STEP per run:
#   admins - static LAN leases for the laptop and the S23, alias Admins, admin ports on the homelab
#            servers and the AdGuard UI only from Admins (LAN, WireGuard), unbound 53530 closed
#            to every client (audit S24)
#   iot    - IOT keeps DNS, NTP and ping to the router plus the flows the homelab uses, then the
#            internet only; the rest is blocked and logged (S16)
#   ssh    - root SSH by key only (S17)
# Idempotent: rules are found by their descr and replaced when they differ. Pre-change backup,
# automatic revert after REVERT_AFTER seconds unless /tmp/homelab-lockdown-STEP-keep appears.
# DRY_RUN=1 prints the changes and writes nothing. SELFTEST=1 runs the edit twice on a copy in /tmp
# and fails unless the second run changes nothing; it applies nothing. No secrets here.

set -eu

STEP="${STEP:?STEP=admins|iot|ssh}"
CONFIG=/conf/config.xml
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="/conf/config.xml.homelab-v2-${STAMP}"
KEEP="/tmp/homelab-lockdown-${STEP}-keep"
CHANGED="/tmp/homelab-lockdown-${STEP}-changed"
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN="${DRY_RUN:-0}"

case "$STEP" in
  admins) APPLY="/usr/local/sbin/configctl filter reload; /usr/local/sbin/configctl dhcpd restart" ;;
  iot) APPLY="/usr/local/sbin/configctl filter reload" ;;
  ssh) APPLY="/usr/local/sbin/configctl openssh restart" ;;
  *) echo "ERROR: unknown STEP $STEP" >&2; exit 2 ;;
esac

edit() {
STEP="$STEP" DRY_RUN="$DRY_RUN" CHANGED="$CHANGED" EDIT_CONFIG="$1" python3 <<'PY'
import os, sys, uuid
import xml.etree.ElementTree as ET

CONFIG = os.environ["EDIT_CONFIG"]
step = os.environ["STEP"]
dry = os.environ.get("DRY_RUN") == "1"
tree = ET.parse(CONFIG)
root = tree.getroot()
filt = root.find("filter")
changes = []

LAPTOP = ("18:db:f2:44:28:f0", "192.168.1.20", "SparkyLinux", "Laptop (Admins)")
PHONE = ("ce:bc:5b:b7:1a:65", "192.168.1.21", "SGS23", "Galaxy S23 (Admins)")
# Also in config/storage.yml prod firewall.ssh_from (the NAS host firewall); change both.
ADMINS = ["192.168.1.20", "192.168.1.21",          # laptop, S23 on LAN
          "10.10.10.2", "10.10.10.4",              # DaveAndroid-Internet, -Local (S23)
          "10.10.10.3", "10.10.10.5"]              # DavePC-Internet, -Local (laptop)


def endpoint(tag, spec, port=None):
    """spec: any | net:<interface or (self)> | addr:<address or alias>; a leading ! negates."""
    e = ET.Element(tag)
    neg, spec = spec.startswith("!"), spec.lstrip("!")
    if spec == "any":
        ET.SubElement(e, "any").text = "1"
    else:
        kind, val = spec.split(":", 1)
        ET.SubElement(e, "network" if kind == "net" else "address").text = val
    if port:
        ET.SubElement(e, "port").text = port
    if neg:
        ET.SubElement(e, "not").text = "1"
    return e


def rule(iface, typ, descr, src, dst, proto=None, port=None, log=False, icmptype=None, floating=False):
    r = ET.Element("rule", uuid=str(uuid.uuid4()))
    for tag, val in (("type", typ), ("interface", iface), ("ipprotocol", "inet"),
                     ("statetype", "keep state"), ("descr", descr), ("direction", "in"), ("quick", "1")):
        ET.SubElement(r, tag).text = val
    if floating:
        ET.SubElement(r, "floating").text = "yes"
    if proto:
        ET.SubElement(r, "protocol").text = proto
    if icmptype:
        ET.SubElement(r, "icmptype").text = icmptype
    if log:
        ET.SubElement(r, "log").text = "1"
    r.append(endpoint("source", src))
    r.append(endpoint("destination", dst, port))
    return r


def shape(e):
    """Compare rules without uuid and audit stamps."""
    keep = [c for c in e if c.tag not in ("created", "updated")]
    return "".join(ET.tostring(c, encoding="unicode").strip() for c in keep)


def ensure_rule(new, before):
    """Insert new above the rule `before`, or replace the rule with the same descr if it differs."""
    descr = new.findtext("descr")
    old = next((r for r in filt.findall("rule") if r.findtext("descr") == descr), None)
    if old is not None:
        if shape(old) == shape(new):
            return
        new.set("uuid", old.get("uuid") or new.get("uuid"))
        kids = list(filt)
        filt.remove(old)
        filt.insert(kids.index(old), new)
        changes.append(f"update rule: {descr}")
        return
    if before is None:
        filt.append(new)
    else:
        filt.insert(list(filt).index(before), new)
    changes.append(f"add rule: {descr}")


def find_rule(pred, what):
    r = next((x for x in filt.findall("rule") if pred(x)), None)
    if r is None:
        sys.exit(f"ERROR: {what} not found as audited, stop")
    return r


def ensure_alias(name, typ, content, description):
    aliases = root.find(".//OPNsense/Firewall/Alias/aliases")
    if aliases is None:
        sys.exit("ERROR: alias section missing, stop")
    text = "\n".join(content)
    old = next((a for a in aliases.findall("alias") if a.findtext("name") == name), None)
    if old is not None:
        if old.findtext("content") != text or old.findtext("type") != typ:
            old.find("content").text = text
            old.find("type").text = typ
            changes.append(f"update alias {name}: {', '.join(content)}")
        return
    a = ET.SubElement(aliases, "alias", uuid=str(uuid.uuid4()))
    for tag, val in (("enabled", "1"), ("name", name), ("type", typ), ("path_expression", None),
                     ("proto", None), ("interface", None), ("counters", "0"), ("updatefreq", None),
                     ("content", text), ("password", None), ("username", None), ("authtype", None),
                     ("categories", None), ("description", description)):
        ET.SubElement(a, tag).text = val
    changes.append(f"add alias {name}: {', '.join(content)}")


def ensure_staticmap(mac, ip, host, descr):
    lan = root.find("dhcpd/lan")
    maps = lan.findall("staticmap")
    clash = [m for m in maps if m.findtext("ipaddr") == ip and m.findtext("mac") != mac]
    if clash:
        sys.exit(f"ERROR: {ip} already mapped to {clash[0].findtext('mac')}, stop")
    old = next((m for m in maps if m.findtext("mac") == mac), None)
    if old is not None:
        if old.findtext("ipaddr") != ip:
            old.find("ipaddr").text = ip
            changes.append(f"update lease {mac} -> {ip}")
        return
    m = ET.Element("staticmap")
    for tag, val in (("mac", mac), ("cid", None), ("ipaddr", ip), ("hostname", host), ("descr", descr),
                     ("winsserver", None), ("dnsserver", None), ("ntpserver", None)):
        ET.SubElement(m, tag).text = val
    after = maps[-1] if maps else None
    lan.insert(list(lan).index(after) + 1 if after is not None else len(lan), m)
    changes.append(f"add lease {mac} {host} -> {ip}")


if step == "admins":
    for mac, ip, host, descr in (LAPTOP, PHONE):
        ensure_staticmap(mac, ip, host, descr)
    ensure_alias("Admins", "host", ADMINS, "homelab-v2: devices with admin access (laptop, S23)")
    ensure_alias("HomelabServers", "host", ["192.168.20.20", "192.168.20.12", "192.168.50.30"],
                 "homelab-v2: Proxmox, NAS, apps")
    ensure_alias("AdminPorts", "port", ["22", "111", "2049", "3128", "5050", "5432", "8006", "8080", "9000", "9443"],
                 "homelab-v2: SSH, NFS, SPICE, pgAdmin, Postgres, Proxmox UI, Dozzle, Portainer")
    ensure_alias("RouterUiPorts", "port", ["80", "8443"], "homelab-v2: AdGuard Home UI")
    lan_pass = find_rule(lambda r: r.findtext("interface") == "lan" and r.findtext("type") == "pass"
                         and r.find("destination/any") is not None, "LAN default allow rule")
    wg_pass = find_rule(lambda r: r.findtext("interface") == "wireguard" and r.findtext("type") == "pass",
                        "WireGuard allow rule")
    for iface, anchor, name in (("lan", lan_pass, "LAN"), ("wireguard", wg_pass, "WG")):
        ensure_rule(rule(iface, "block", f"homelab-v2 {name} admin ports only from Admins", "!addr:Admins",
                         "addr:HomelabServers", "tcp/udp", "AdminPorts", log=True), anchor)
        ensure_rule(rule(iface, "block", f"homelab-v2 {name} AdGuard UI only from Admins", "!addr:Admins",
                         "net:(self)", "tcp", "RouterUiPorts", log=True), anchor)
    # Floating rules are evaluated before the interface rules wherever they sit in the file.
    first = filt.findall("rule")[0]
    ensure_rule(rule("lan,opt1,opt2,opt3,opt4,opt5,opt6,wireguard", "block",
                     "homelab-v2 unbound 53530 not for clients", "any", "net:(self)", "tcp/udp", "53530",
                     log=True, floating=True), first)

elif step == "iot":
    ensure_alias("BeszelAgentsIot", "host", ["192.168.20.12", "192.168.20.13", "192.168.20.20"],
                 "homelab-v2: Beszel agents on IOT (NAS, Home Assistant, Proxmox)")
    ensure_alias("AppCheckersIot", "host", ["192.168.20.13", "192.168.20.14"],
                 "homelab-v2: Uptime Kuma on the T620 and the prod runner")
    internet = find_rule(lambda r: r.findtext("interface") == "opt3" and r.findtext("type") == "pass"
                         and r.find("destination/not") is not None, "IOT internet rule")
    for new in (
        rule("opt3", "pass", "homelab-v2 IOT NTP to the router", "net:opt3", "net:opt3ip", "udp", "123"),
        rule("opt3", "pass", "homelab-v2 IOT ping the router", "net:opt3", "net:opt3ip", "icmp", icmptype="echoreq"),
        rule("opt3", "pass", "homelab-v2 NAS SSH to the router (config backup)", "addr:192.168.20.12",
             "net:opt3ip", "tcp", "22"),
        rule("opt3", "pass", "homelab-v2 Beszel agents to the hub", "addr:BeszelAgentsIot",
             "addr:192.168.50.30", "tcp", "8090"),
        rule("opt3", "pass", "homelab-v2 NAS photo watcher to Immich", "addr:192.168.20.12",
             "addr:192.168.50.30", "tcp", "2283"),
        rule("opt3", "pass", "homelab-v2 Proxmox NIC error mail to apps", "addr:192.168.20.20",
             "addr:192.168.50.30", "tcp", "22"),
        rule("opt3", "pass", "homelab-v2 Kuma and the prod runner to apps", "addr:AppCheckersIot",
             "addr:192.168.50.30", "tcp"),
        rule("opt3", "pass", "homelab-v2 Kuma to public Grocery on the WAN address", "addr:192.168.20.13",
             "addr:192.168.100.2", "tcp", "443"),
    ):
        ensure_rule(new, internet)
    # The internet rule used to exclude only HOME OFFICE and GUEST (NotForIOT).
    want = rule("opt3", "pass", "homelab-v2 IOT to the internet only", "net:opt3", "!addr:PrivateNetworks")
    if shape(internet) != shape(want):
        idx = list(filt).index(internet)
        want.set("uuid", internet.get("uuid"))
        filt.remove(internet)
        filt.insert(idx, want)
        changes.append("update rule: IOT internet -> !PrivateNetworks (was !NotForIOT)")
        internet = want
    kids = list(filt)
    nxt = kids[kids.index(internet) + 1] if kids.index(internet) + 1 < len(kids) else None
    ensure_rule(rule("opt3", "block", "homelab-v2 IOT block the rest", "net:opt3", "any", log=True), nxt)

elif step == "ssh":
    ssh = root.find("system/ssh")
    pw = ssh.find("passwordauth")
    if pw is not None:
        ssh.remove(pw)
        changes.append("ssh: password and keyboard-interactive login off (root keeps key login)")
    if ssh.find("permitrootlogin") is None:
        sys.exit("ERROR: root login is off already; the NAS backup key needs it, stop")

for c in changes:
    print(("would " if dry else "") + c)
if changes and not dry:
    tree.write(CONFIG, encoding="UTF-8", xml_declaration=True)
    print("config written")
open(os.environ["CHANGED"], "w").write("1" if changes else "0")
PY
}

if [ "${SELFTEST:-0}" = 1 ]; then
  copy="/tmp/homelab-lockdown-selftest.xml"
  cp "$CONFIG" "$copy"
  DRY_RUN=0
  edit "$copy" >/dev/null
  first=$(cat "$CHANGED")
  second=$(edit "$copy")
  rm -f "$copy" "$CHANGED"
  [ -z "$second" ] || { echo "SELFTEST FAIL: a second run still changes: $second"; exit 1; }
  echo "selftest ok: first run changed=${first}, second run changed nothing"
  exit 0
fi

[ "$DRY_RUN" = 1 ] || { cp "$CONFIG" "$BACKUP"; echo "Backup on router: $BACKUP"; }
edit "$CONFIG"

[ "$DRY_RUN" = 1 ] && { echo "dry run - nothing written"; exit 0; }
[ "$(cat "$CHANGED")" = 1 ] || { rm -f "$BACKUP"; echo "nothing to change"; exit 0; }

rm -f "$KEEP"
sh -c "$APPLY"
echo "applied: $APPLY"
daemon -f -P "/tmp/homelab-lockdown-${STEP}-revert.pid" sh -c "sleep ${REVERT_AFTER}; [ -f ${KEEP} ] || { cp ${BACKUP} ${CONFIG}; ${APPLY}; echo reverted > /tmp/homelab-lockdown-${STEP}-reverted; }"
echo "auto-revert armed: ${REVERT_AFTER}s, cancel with: touch ${KEEP}"
echo "manual revert: cp ${BACKUP} ${CONFIG} && ${APPLY}"
