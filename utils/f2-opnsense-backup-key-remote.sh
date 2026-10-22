#!/usr/bin/env sh
# Run ON OPNsense as root (piped via SSH). Adds the NAS backup key to root's authorized keys with a
# forced command, so the key can only print config.xml (utils/backup/opnsense.sh on the NAS).
# PUBKEY = "ssh-ed25519 AAAA... comment" from the wrapper. Idempotent. Pre-change backup, automatic
# revert after REVERT_AFTER seconds unless /tmp/homelab-backupkey-keep appears. DRY_RUN=1: no write.
# Do not store secrets in this file.

set -eu

CONFIG=/conf/config.xml
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="/conf/config.xml.homelab-v2-${STAMP}"
KEEP=/tmp/homelab-backupkey-keep
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN="${DRY_RUN:-0}"
: "${PUBKEY:?PUBKEY is required}"

[ "$DRY_RUN" = 1 ] || { cp "$CONFIG" "$BACKUP"; echo "Backup on router: $BACKUP"; }

DRY_RUN="$DRY_RUN" PUBKEY="$PUBKEY" python3 <<'PY'
import base64, os, sys
import xml.etree.ElementTree as ET

CONFIG = "/conf/config.xml"
dry = os.environ.get("DRY_RUN") == "1"
pub = os.environ["PUBKEY"].strip()
if not pub.startswith("ssh-ed25519 ") or "\n" in pub:
    sys.exit("ERROR: PUBKEY is not one ssh-ed25519 public key line, stop")
line = f'command="cat /conf/config.xml",restrict {pub}'
tree = ET.parse(CONFIG)
root = [u for u in tree.getroot().find("system").findall("user") if u.findtext("name") == "root"]
if len(root) != 1:
    sys.exit("ERROR: expected exactly one user root in config.xml, stop")
node = root[0].find("authorizedkeys")
current = base64.b64decode(node.text or "").decode() if node is not None else ""
keys = [k for k in current.splitlines() if k.strip()]
if any(pub.split()[1] in k for k in keys):
    print("backup key present - skip")
    changed = False
else:
    if not keys:
        sys.exit("ERROR: root has no authorized key today - adding one would be the only way in, stop")
    keys.append(line)
    if node is None:
        node = ET.SubElement(root[0], "authorizedkeys")
    node.text = base64.b64encode(("\n".join(keys) + "\n").encode()).decode()
    print(f"add: root authorized key with forced command ({len(keys)} keys)")
    changed = True
if changed and not dry:
    tree.write(CONFIG, encoding="UTF-8", xml_declaration=True)
    print("config written")
open("/tmp/homelab-backupkey-changed", "w").write("1" if changed else "0")
PY

[ "$DRY_RUN" = 1 ] && { echo "dry run - nothing written"; exit 0; }
[ "$(cat /tmp/homelab-backupkey-changed)" = 1 ] || { rm -f "$BACKUP"; echo "nothing to change"; exit 0; }

rm -f "$KEEP"
/usr/local/sbin/configctl auth sync user root
echo "authorized_keys of root: $(grep -c . /root/.ssh/authorized_keys) keys"
daemon -f -P /tmp/homelab-backupkey-revert.pid sh -c "sleep ${REVERT_AFTER}; [ -f ${KEEP} ] || { cp ${BACKUP} ${CONFIG}; /usr/local/sbin/configctl auth sync user root; echo reverted > /tmp/homelab-backupkey-reverted; }"
echo "auto-revert armed: ${REVERT_AFTER}s, cancel with: touch ${KEEP}"
echo "manual revert: cp ${BACKUP} ${CONFIG} && configctl auth sync user root"
