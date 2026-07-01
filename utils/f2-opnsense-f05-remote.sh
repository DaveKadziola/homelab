#!/usr/bin/env sh
# F2-05 on OPNsense: ACME cert for grocery.dkhomelabserver.xyz (DNS-01 via existing CF).
# HAProxy frontend/backend — enable service; full grocery routing in F4/UI if needed.
# Run ON router as root (piped via SSH).

set -eu

CONFIG=/conf/config.xml
DOMAIN=grocery.dkhomelabserver.xyz
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="/conf/config.xml.f2-05-${STAMP}"

cp "$CONFIG" "$BACKUP"
echo "Backup: $BACKUP"

python3 <<'PY'
import copy
import subprocess
import sys
import uuid
import xml.etree.ElementTree as ET

CONFIG = "/conf/config.xml"
DOMAIN = "grocery.dkhomelabserver.xyz"
ACCOUNT = "ff2161c3-7f17-4679-9c64-8586d4c08275"
VALIDATION = "494d25da-003e-459d-8602-c85ab4a8a0b5"

tree = ET.parse(CONFIG)
root = tree.getroot()
acme = root.find(".//AcmeClient")
if acme is None:
    print("ERROR: AcmeClient section missing", file=sys.stderr)
    sys.exit(1)

certs = acme.find("certificates")
if certs is None:
    certs = ET.SubElement(acme, "certificates")

for cert in certs.findall("certificate"):
    name = cert.findtext("name") or ""
    if name == DOMAIN:
        print(f"ACME cert entry already exists: {DOMAIN}")
        cert_uuid = cert.get("uuid")
        break
else:
    # Clone proxmox cert as template
    template = None
    for cert in certs.findall("certificate"):
        if (cert.findtext("name") or "").startswith("proxmox."):
            template = cert
            break
    if template is None:
        template = certs.find("certificate")
    if template is None:
        print("ERROR: no ACME cert template found", file=sys.stderr)
        sys.exit(1)

    cert_uuid = str(uuid.uuid4())
    new_cert = copy.deepcopy(template)
    new_cert.set("uuid", cert_uuid)
    for tag in ("id", "certRefId", "lastUpdate", "statusCode", "statusLastUpdate"):
        el = new_cert.find(tag)
        if el is not None:
            new_cert.remove(el)
    ET.SubElement(new_cert, "id").text = uuid.uuid4().hex[:16]
    name_el = new_cert.find("name")
    if name_el is not None:
        name_el.text = DOMAIN
    desc = new_cert.find("description")
    if desc is not None:
        desc.text = "Grocery public HTTPS (homelab v2 F2-05)"
    else:
        ET.SubElement(new_cert, "description").text = "Grocery public HTTPS (homelab v2 F2-05)"
    certs.append(new_cert)
    print(f"Added ACME cert entry: {DOMAIN} uuid={cert_uuid}")

tree.write(CONFIG, encoding="UTF-8", xml_declaration=True)
subprocess.run(["/usr/local/sbin/configctl", "acmeclient", "reload"], check=False)

# Issue / renew certificate
r = subprocess.run(
    ["/usr/local/sbin/configctl", "acmeclient", "issue", cert_uuid],
    capture_output=True,
    text=True,
)
print(r.stdout or "", end="")
if r.stderr:
    print(r.stderr, file=sys.stderr, end="")
if r.returncode != 0:
    print(f"WARN: acmeclient issue exit {r.returncode} — check UI / DNS", file=sys.stderr)

# Enable HAProxy (frontends still empty — F4 backend port)
haproxy = root.find(".//HAProxy")
if haproxy is not None:
    general = haproxy.find("general")
    if general is not None:
        enabled = general.find("enabled")
        if enabled is not None and enabled.text != "1":
            enabled.text = "1"
            tree.write(CONFIG, encoding="UTF-8", xml_declaration=True)
            subprocess.run(["/usr/local/sbin/configctl", "haproxy", "reload"], check=False)
            print("HAProxy enabled (add frontend/backend in UI or F4)")
        else:
            print("HAProxy already enabled or general section missing")
PY

echo "--- Public IP (for DNS A record) ---"
curl -fsS --max-time 5 ifconfig.me 2>/dev/null || echo "(could not detect — set A record manually)"
echo ""
echo "Ensure Cloudflare A record: ${DOMAIN} -> WAN public IP"
echo "HAProxy: Services -> HAProxy -> frontend WAN:443 + backend ${DOMAIN} -> 192.168.50.30:<port> (F4)"
