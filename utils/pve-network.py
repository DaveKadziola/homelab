#!/usr/bin/env python3
"""Write config/pve/interfaces.<env> to /etc/network/interfaces on the Proxmox host, with auto-revert.

  [PVE_KEY=~/.ssh/<root key>] utils/pve-network.py --env prod --dry-run
  [PVE_KEY=~/.ssh/<root key>] utils/pve-network.py --env prod
  utils/pve-network.py --self-test

Host: prod PROXMOX_IP (default 192.168.20.20), dev DEV_PROXMOX_IP (default 192.168.122.219).
Prints the diff host -> repo; no diff, no change. Otherwise: backup on the host, a systemd timer
that restores it after REVERT_AFTER seconds (default 300), write, ifreload -a. New SSH connections
then check the file, the ifreload result, every `auto` interface UP, and SSH (:22) on each guest
in the env's tfvars that answered before; only then is the timer stopped. Stops when the host
name is not proxmox_node_name of that env, a GUI change is pending (/etc/network/interfaces.new)
or an earlier run's revert is still pending. Fresh install: docs/f3-proxmox.md instead.
Exit code: 0 ok or no change, 1 stop or failure, 2 usage error.
"""
import argparse
import difflib
import os
import re
import socket
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOSTS = {"prod": ("PROXMOX_IP", "192.168.20.20"), "dev": ("DEV_PROXMOX_IP", "192.168.122.219")}
UNIT = "homelab-pve-network"
STAGE = f"/run/{UNIT}.new"
OK = f"/run/{UNIT}.ok"


def node_name(tfvars):
    m = re.search(r'^proxmox_node_name\s*=\s*"([^"]*)"', tfvars, re.M)
    return m.group(1) if m else ""


def guest_ips(tfvars):
    return re.findall(r'^\s*cloud_init_cidr\s*=\s*"([0-9.]+)/\d+"', tfvars, re.M)


def auto_interfaces(text):
    out = []
    for line in text.splitlines():
        words = line.split()
        if words and words[0] == "auto":
            out += [w for w in words[1:] if w != "lo"]
    return out


def up_interfaces(ip_br_link):
    # `ip -br link` names VLAN devices `vmbr0.20@vmbr0`; the file names them `vmbr0.20`.
    return {w[0].split("@")[0] for w in (l.split() for l in ip_br_link.splitlines()) if len(w) > 1 and w[1] == "UP"}


def diff_lines(host_bytes, repo_bytes, host_label, repo_label):
    """None when the files are byte-identical, otherwise the unified diff lines host -> repo."""
    if host_bytes == repo_bytes:
        return None
    lines = list(difflib.unified_diff(host_bytes.decode(errors="replace").splitlines(),
                                      repo_bytes.decode(errors="replace").splitlines(),
                                      host_label, repo_label, lineterm=""))
    return lines or ["(files differ only in line endings or the final newline)"]


def reach(ip):
    try:
        socket.create_connection((ip, 22), timeout=3).close()
        return True
    except OSError:
        return False


class Host:
    def __init__(self, addr, key):
        # ControlPath=none: every call opens its own connection, so the checks after ifreload use a
        # new one. Keepalives end a session stalled by the address move instead of hanging.
        self.addr = addr
        self.ssh = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=5",
                    "-o", "ServerAliveCountMax=3", "-o", "ControlPath=none"]
        if key:
            self.ssh += ["-i", os.path.expanduser(key)]
        self.ssh.append(f"root@{addr}")

    def run(self, snippet, data=None, remote="sh -s", may_drop=False):
        """Run a small shell snippet on the host (stdin, no nested quoting); returns (code, stdout bytes)."""
        stdin = data if data is not None else snippet.encode()
        res = subprocess.run(self.ssh + [remote], input=stdin, capture_output=True)
        sys.stderr.write(res.stderr.decode(errors="replace"))
        if res.returncode == 255 and not may_drop:
            sys.exit(f"STOP: ssh to root@{self.addr} failed")
        return res.returncode, res.stdout


def apply_snippet(backup, revert_after):
    # Own units: the revert timer and ifreload survive this SSH session dying with the old link.
    return f"""set -eu
rm -f {OK}
cp -p /etc/network/interfaces {backup}
echo "backup on host: {backup}"
systemd-run -q -G --unit={UNIT}-revert --on-active={revert_after} --timer-property=RemainAfterElapse=no \\
  sh -c 'cp {backup} /etc/network/interfaces && ifreload -a'
echo "auto-revert armed: {revert_after}s"
cp {STAGE} /etc/network/interfaces
systemd-run -q -G --wait --unit={UNIT}-apply sh -c 'ifreload -a && touch {OK}'
"""


def confirm_snippet():
    # Timer first, so it cannot fire after the checks. A revert start job still queued (stopping the
    # timer does not cancel it), a revert service not at rest, or the file no longer the repo's
    # means the revert won: not kept. -G collects the finished service, so at rest is "inactive".
    return f"""set -e
systemctl stop {UNIT}-revert.timer
[ -z "$(systemctl list-jobs --no-legend '{UNIT}-revert.*')" ]
[ "$(systemctl is-active {UNIT}-revert.service)" = inactive ]
cmp -s {STAGE} /etc/network/interfaces
rm -f {STAGE} {OK}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--env", choices=sorted(HOSTS))
    parser.add_argument("--dry-run", action="store_true", help="show the diff, change nothing")
    parser.add_argument("--self-test", action="store_true", help="test the parsing, no host")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if not args.env:
        parser.error("--env prod|dev is required")
    revert_after = os.environ.get("REVERT_AFTER", "300")
    # It goes into a remote shell line: digits only.
    if not revert_after.isdigit() or int(revert_after) == 0:
        parser.error("REVERT_AFTER must be a whole number of seconds")

    var, default = HOSTS[args.env]
    host = Host(os.environ.get(var) or default, os.environ.get("PVE_KEY"))
    src = ROOT / "config" / "pve" / f"interfaces.{args.env}"
    if not src.is_file():
        sys.exit(f"missing config/pve/interfaces.{args.env}")
    want = src.read_bytes()
    tfvars = (ROOT / "terraform" / "environments" / args.env / "terraform.tfvars").read_text(encoding="utf-8")
    node = node_name(tfvars)

    name = host.run("hostname")[1].decode().strip()
    if not node or name != node:
        sys.exit(f"STOP: {host.addr} is '{name}', --env {args.env} expects '{node}'")
    # PVE moves a pending GUI change (interfaces.new) over /etc/network/interfaces at the next boot.
    if host.run("test ! -e /etc/network/interfaces.new")[0]:
        sys.exit(f"STOP: /etc/network/interfaces.new exists on {host.addr} - apply or revert the pending change in the GUI first")
    # After a failed run the repo file is on the host and its revert is still armed: no diff, but not kept.
    if host.run(f"! systemctl is-active --quiet {UNIT}-revert.timer {UNIT}-revert.service {UNIT}-apply.service")[0]:
        sys.exit(f"STOP: an earlier run is still pending on {host.addr} ({UNIT}-revert.timer) - wait for its revert")

    code, have = host.run("cat /etc/network/interfaces")
    if code:
        sys.exit(f"STOP: cannot read /etc/network/interfaces on {host.addr}")
    diff = diff_lines(have, want, f"{host.addr}:/etc/network/interfaces", f"config/pve/interfaces.{args.env}")
    if diff is None:
        print("no change")
        return 0
    print("\n".join(diff))
    if args.dry_run:
        print("dry run - nothing changed")
        return 0

    # Guests on SSH (:22), the port the Ansible deploys use; a guest down before the change is skipped.
    guests = []
    for ip in guest_ips(tfvars):
        if reach(ip):
            guests.append(ip)
        else:
            print(f"skip  guest {ip}: no SSH answer before the change")

    backup = f"/etc/network/interfaces.homelab-v2-{time.strftime('%Y%m%d-%H%M%S')}"
    if host.run("", data=want, remote=f"cat > {STAGE}")[0]:
        sys.exit(f"STOP: cannot stage the file in {STAGE}")
    # The session can drop while ifreload moves the management address; the checks below decide.
    code, out = host.run(apply_snippet(backup, revert_after), may_drop=True)
    print(out.decode(errors="replace"), end="", flush=True)
    if code:
        print(f"apply session ended with code {code} - checking over a new connection")

    time.sleep(5)
    fail = False

    def check(label, ok):
        nonlocal fail
        print(f"{'ok  ' if ok else 'FAIL'}  {label}")
        fail = fail or not ok

    check(f"new SSH connection to {host.addr}, repo file in place",
          host.run(f"cmp -s {STAGE} /etc/network/interfaces", may_drop=True)[0] == 0)
    check("ifreload -a succeeded", host.run(f"test -e {OK}", may_drop=True)[0] == 0)
    up = up_interfaces(host.run("ip -br link", may_drop=True)[1].decode(errors="replace"))
    for iface in auto_interfaces(want.decode(errors="replace")):
        check(f"{iface} UP", iface in up)
    for ip in guests:
        check(f"guest {ip} answers SSH", reach(ip))

    manual = f"manual revert: cp {backup} /etc/network/interfaces && ifreload -a"
    if not fail and host.run(confirm_snippet(), may_drop=True)[0] == 0:
        print("all checks passed - change kept")
        print(manual)
        return 0
    print("not confirmed (a check failed, the revert fired first, or the confirm step did not finish)")
    # Ask again over a new connection: the confirm step may have stopped the timer before it failed.
    code = host.run(f"systemctl is-active --quiet {UNIT}-revert.timer {UNIT}-revert.service", may_drop=True)[0]
    if code == 0:
        print(f"revert armed or running: the host restores {backup} within {revert_after}s")
    else:
        print(f"revert {'state unknown (no SSH)' if code == 255 else 'not pending (it ran, or the timer was stopped)'}"
              f" - check /etc/network/interfaces on the host; {manual}")
    return 1


def self_test():
    tf = ('# comment\nproxmox_node_name   = "proxmox"\nmanage_node_network = false\n'
          'vm_config = {\n  nas = {\n    cloud_init_cidr    = "192.168.20.12/24"\n    cloud_init_gateway = "192.168.20.1"\n  }\n'
          '  apps = {\n    cloud_init_cidr    = "192.168.50.30/26"\n    cloud_init_dns     = "192.168.50.50" # own gateway\n  }\n}\n')
    assert node_name(tf) == "proxmox"
    assert node_name('# proxmox_node_name = "x"\n') == ""
    assert guest_ips(tf) == ["192.168.20.12", "192.168.50.30"]
    assert guest_ips('# cloud_init_cidr = "1.2.3.4/24"\n') == []

    ifaces = ("auto lo\niface lo inet loopback\n\niface nic0 inet manual\n# auto commented\n"
              "auto bond0\niface bond0 inet manual\n\tbond-slaves nic1 nic0\nauto vmbr0 vmbr0.20\n"
              "auto vmbr1\nsource /etc/network/interfaces.d/*\n")
    assert auto_interfaces(ifaces) == ["bond0", "vmbr0", "vmbr0.20", "vmbr1"], auto_interfaces(ifaces)

    links = ("lo               UNKNOWN        00:00:00:00:00:00 <LOOPBACK,UP,LOWER_UP>\n"
             "nic0             UP             70:85:c2:53:e0:ac <BROADCAST,MULTICAST,SLAVE,UP,LOWER_UP>\n"
             "bond0            UP             3c:49:37:19:71:ae <BROADCAST,MULTICAST,MASTER,UP,LOWER_UP>\n"
             "vmbr0.20@vmbr0   UP             3c:49:37:19:71:ae <BROADCAST,MULTICAST,UP,LOWER_UP>\n"
             "vmbr1            DOWN           3c:49:37:19:71:af <NO-CARRIER,BROADCAST,MULTICAST,UP>\n"
             "tap101i0         UNKNOWN        aa:bb:cc:dd:ee:ff <BROADCAST,MULTICAST,UP>\n\n")
    up = up_interfaces(links)
    assert up == {"nic0", "bond0", "vmbr0.20"}, up
    assert "vmbr1" not in up and "lo" not in up

    assert diff_lines(b"a\nb\n", b"a\nb\n", "h", "r") is None
    d = diff_lines(b"a\nb\n", b"a\nc\n", "h", "r")
    assert d[:2] == ["--- h", "+++ r"] and "-b" in d and "+c" in d, d
    assert diff_lines(b"a\n", b"a", "h", "r") == ["(files differ only in line endings or the final newline)"]

    snip = apply_snippet("/etc/network/interfaces.homelab-v2-20261020-120000", "300")
    assert "--on-active=300 --timer-property=RemainAfterElapse=no" in snip
    assert snip.index("--unit=homelab-pve-network-revert") < snip.index(f"cp {STAGE} /etc/network/interfaces")
    conf = confirm_snippet().splitlines()
    assert conf[:2] == ["set -e", "systemctl stop homelab-pve-network-revert.timer"], conf
    assert "list-jobs" in conf[2] and "is-active" in conf[3] and conf[4].startswith("cmp -s"), conf
    assert conf[-1].startswith("rm -f"), conf
    print("self-test ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
