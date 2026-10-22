#!/usr/bin/env sh
# Run ON OPNsense as root (piped via SSH). Adds the AdGuard Home rewrites for the app names
# (decision 0007): REWRITES = lines "name ip" from the wrapper. Only adds missing names; a name that
# exists with another answer stops the run (no guessing), other rewrites are never touched.
# AdGuard is stopped while its YAML is edited (it rewrites the file itself). Idempotent. Pre-change
# backup, automatic revert after REVERT_AFTER seconds unless /tmp/homelab-rewrites-keep appears.
# DRY_RUN=1: no write. Do not store secrets in this file.

set -eu

CONFIG=/usr/local/AdGuardHome/AdGuardHome.yaml
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="${CONFIG}.homelab-v2-${STAMP}"
KEEP=/tmp/homelab-rewrites-keep
REVERT_AFTER="${REVERT_AFTER:-300}"
DRY_RUN="${DRY_RUN:-0}"
: "${REWRITES:?REWRITES is required}"

python3 - "$CONFIG" > /tmp/homelab-rewrites-plan <<'PY'
import os, re, sys
import yaml

cfg = sys.argv[1]
want = [line.split() for line in os.environ["REWRITES"].splitlines() if line.strip()]
for w in want:
    if len(w) != 2 or not re.fullmatch(r"[a-z0-9.-]+\.dkhomelabserver\.xyz", w[0]) or not re.fullmatch(r"[0-9.]+", w[1]):
        sys.exit(f"ERROR: bad rewrite line {w!r}, stop")
have = {r["domain"]: r for r in (yaml.safe_load(open(cfg))["filtering"].get("rewrites") or [])}
for name, ip in want:
    r = have.get(name)
    if r is None:
        print(f"add {name} {ip}")
    elif r.get("answer") != ip or r.get("enabled") is False:
        sys.exit(f"ERROR: {name} exists with answer {r.get('answer')} enabled={r.get('enabled')} - fix by hand, stop")
PY
cat /tmp/homelab-rewrites-plan
[ -s /tmp/homelab-rewrites-plan ] || { echo "nothing to change"; exit 0; }
[ "$DRY_RUN" = 1 ] && { echo "dry run - nothing written"; exit 0; }

cp "$CONFIG" "$BACKUP"; echo "Backup on router: $BACKUP"
/usr/local/etc/rc.d/adguardhome stop
python3 - "$CONFIG" <<'PY'
import sys
cfg = sys.argv[1]
lines = open(cfg).read().split("\n")
at = lines.index("  rewrites:") + 1
new = []
for row in open("/tmp/homelab-rewrites-plan").read().split("\n"):
    if row.startswith("add "):
        _, name, ip = row.split()
        new += [f"    - domain: {name}", f"      answer: {ip}", "      enabled: true"]
lines[at:at] = new
open(cfg, "w").write("\n".join(lines))
print(f"config written: {len(new) // 3} rewrites added")
PY
/usr/local/etc/rc.d/adguardhome start
rm -f "$KEEP"
daemon -f -P /tmp/homelab-rewrites-revert.pid sh -c "sleep ${REVERT_AFTER}; [ -f ${KEEP} ] || { /usr/local/etc/rc.d/adguardhome stop; cp ${BACKUP} ${CONFIG}; /usr/local/etc/rc.d/adguardhome start; echo reverted > /tmp/homelab-rewrites-reverted; }"
echo "auto-revert armed: ${REVERT_AFTER}s, cancel with: touch ${KEEP}"
echo "manual revert: /usr/local/etc/rc.d/adguardhome stop; cp ${BACKUP} ${CONFIG}; /usr/local/etc/rc.d/adguardhome start"
