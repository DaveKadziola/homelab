#!/usr/bin/env sh
# Run ON OPNsense as root (piped via SSH). Idempotent F2-03 + pre-change backup.
# Do not store secrets in this file.

set -eu

CONFIG=/conf/config.xml
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="/conf/config.xml.homelab-v2-${STAMP}"

cp "$CONFIG" "$BACKUP"
echo "Backup on router: $BACKUP"

python3 <<'PY'
import xml.etree.ElementTree as ET
import subprocess
import sys

CONFIG = "/conf/config.xml"
MARKER = "homelab-v2 NFS APP to NAS"
NAS_IP = "192.168.20.12"
PORTS = ("2049", "111")

tree = ET.parse(CONFIG)
root = tree.getroot()

# Find APP interface (QinQ / 192.168.50.50)
app_if = None
for ifname in root.findall(".//interfaces/*"):
    tag = ifname.tag
    ip = ifname.findtext("ipaddr")
    descr = (ifname.findtext("descr") or "").lower()
    if ip and ip.startswith("192.168.50.50"):
        app_if = tag
        break
    if "app" in descr or "qinq" in descr:
        ip = ifname.findtext("ipaddr") or ""
        if ip.startswith("192.168.50."):
            app_if = tag

if not app_if:
    print("ERROR: could not detect APP interface (expected 192.168.50.50)", file=sys.stderr)
    sys.exit(1)

print(f"APP interface: {app_if}")

filter_node = root.find("filter")
if filter_node is None:
    filter_node = ET.SubElement(root, "filter")

existing = []
for rule in filter_node.findall("rule"):
    descr = rule.findtext("descr") or ""
    if MARKER in descr or NAS_IP in ET.tostring(rule, encoding="unicode"):
        existing.append(rule)

if existing:
    print(f"NFS rule already present ({len(existing)} matching rule(s)) — skip")
else:
    for port in PORTS:
        rule = ET.SubElement(filter_node, "rule")
        ET.SubElement(rule, "type").text = "pass"
        ET.SubElement(rule, "ipprotocol").text = "inet"
        ET.SubElement(rule, "descr").text = f"{MARKER} TCP {port}"
        ET.SubElement(rule, "interface").text = app_if
        ET.SubElement(rule, "direction").text = "in"
        ET.SubElement(rule, "quick").text = "1"
        src = ET.SubElement(rule, "source")
        ET.SubElement(src, "network").text = app_if
        dst = ET.SubElement(rule, "destination")
        ET.SubElement(dst, "address").text = f"{NAS_IP}/32"
        ET.SubElement(rule, "protocol").text = "TCP"
        ET.SubElement(rule, "destinationport").text = port
        print(f"Added rule: {app_if} -> {NAS_IP}:{port}")

tree.write(CONFIG, encoding="UTF-8", xml_declaration=True)
subprocess.run(["/usr/local/sbin/configctl", "filter", "reload"], check=True)
print("filter reload OK")
PY

echo "--- DHCP static maps (homelab v2 targets) ---"
grep -E "192.168.20.12|192.168.20.13|192.168.50.30" "$CONFIG" || echo "(none yet — add MAC at F3/F5)"

echo "--- NFS rules ---"
grep -i "homelab-v2 NFS\|192.168.20.12" "$CONFIG" | head -10 || true
