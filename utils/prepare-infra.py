#!/usr/bin/env python3
"""Prepare the network and the Proxmox host so a pipeline has a target.

  utils/prepare-infra.py --env dev
  utils/prepare-infra.py --env dev --dry-run
  utils/prepare-infra.py --env prod
  utils/prepare-infra.py --self-test

DEV starts the nested Proxmox, records its API URL in the GitHub dev
environment, writes the host network (utils/pve-network.py) and starts the
HAOS twin. prod only checks: the host answers, and the network file matches.
It does not change the router, the host network, or the VMs.

This does not run terraform and does not start a GitHub workflow. A local
apply races with Infra Apply (knowledge/rebuild.md). The API token and the
app secrets are checked by name. A missing name stops the run; the value is
never printed.
"""

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "DaveKadziola/homelab"
# Names deploy-core.yml refuses to continue without, plus the Proxmox API token
# the infra pipeline needs. Checked with `gh secret list`, which prints names.
REQUIRED = (
    "PROXMOX_API_TOKEN_SECRET",
    "POSTGRES_PASSWORD",
    "HOMARR_SECRET_KEY",
    "LINKWARDEN_SECRET",
    "PGADMIN_PASSWORD",
    "GROCERY_SECRET_KEY",
)


def dev_steps(dry):
    network = [sys.executable, "utils/pve-network.py", "--env", "dev"]
    haos = ["utils/dev-haos-vm.sh"]
    if dry:
        network.append("--dry-run")
        haos.append("--dry-run")
    return [
        ["utils/ensure-dev-proxmox.sh"],
        ["utils/bootstrap-dev-proxmox.sh"],
        network,
        haos,
    ]


def prod_steps():
    return [[sys.executable, "utils/pve-network.py", "--env", "prod", "--dry-run"]]


def missing_secrets(env):
    out = subprocess.run(
        ["gh", "secret", "list", "--env", env, "--repo", REPO],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    have = {line.split()[0] for line in out.stdout.splitlines() if line.strip()}
    return [name for name in REQUIRED if name not in have]


def proxmox_answers(ip):
    probe = subprocess.run(
        ["curl", "-fsSk", "--max-time", "5", "-o", "/dev/null", f"https://{ip}:8006/"],
        cwd=ROOT,
    )
    return probe.returncode == 0


def run_steps(steps, dry, skip_when_dry):
    for cmd in steps:
        shown = " ".join(cmd)
        if dry and cmd[0] in skip_when_dry:
            print(f"would: {shown}")
            continue
        print(f"+ {shown}")
        result = subprocess.run(cmd, cwd=ROOT)
        if result.returncode != 0:
            print(f"STOP: {shown} exited {result.returncode}", file=sys.stderr)
            return result.returncode
    return 0


def prepare(env, dry):
    if env == "prod":
        if not proxmox_answers("192.168.20.20"):
            print("STOP: Proxmox at 192.168.20.20:8006 did not answer", file=sys.stderr)
            return 1
        code = run_steps(prod_steps(), dry=False, skip_when_dry=())
    else:
        code = run_steps(
            dev_steps(dry),
            dry=dry,
            skip_when_dry={"utils/ensure-dev-proxmox.sh", "utils/bootstrap-dev-proxmox.sh"},
        )
    if code != 0:
        return code
    try:
        missing = missing_secrets(env)
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"STOP: could not list GitHub secret names ({type(exc).__name__})", file=sys.stderr)
        return 1
    if missing:
        print("missing: " + " ".join(missing))
        print(f"create them with utils/gen-app-credentials.sh --env {env}")
        if "PROXMOX_API_TOKEN_SECRET" in missing and env == "dev":
            print("the Proxmox API token is utils/bootstrap-dev-proxmox.sh --set-token")
        return 1
    print(f"{env}: host is ready for the pipeline. This script does not start it.")
    return 0


def self_test():
    dry = dev_steps(True)
    live = dev_steps(False)
    assert dry[2][-1] == "--dry-run" and dry[3][-1] == "--dry-run"
    assert "--dry-run" not in live[2] and "--dry-run" not in live[3]
    assert live[0] == ["utils/ensure-dev-proxmox.sh"]
    assert live[1] == ["utils/bootstrap-dev-proxmox.sh"]
    prod = prod_steps()
    assert prod == [[sys.executable, "utils/pve-network.py", "--env", "prod", "--dry-run"]]
    assert not any("dev-apply-local" in " ".join(c) or "workflow" in " ".join(c) for c in live + prod)
    print("self-test ok")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--env", choices=("dev", "prod"))
    parser.add_argument("--dry-run", action="store_true", help="print the DEV steps that change state; still read the DEV network diff")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    if not args.env:
        parser.error("--env dev|prod is required")
    return prepare(args.env, args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
