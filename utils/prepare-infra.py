#!/usr/bin/env python3
"""Prepare the network and the Proxmox host so a pipeline has a target.

  utils/prepare-infra.py --env dev
  utils/prepare-infra.py --env dev --dry-run
  utils/prepare-infra.py --env prod
  utils/prepare-infra.py --self-test

The first step lists missing secret names. Names that
utils/gen-app-credentials.sh creates are filled, then the list is checked
again. A missing Proxmox API token is printed and the run stops before any
host change. DEV then starts the nested Proxmox, records its API URL,
writes the host network (utils/pve-network.py) and starts the HAOS twin.
prod only checks: the host answers, and the network file matches.
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
# Not created by gen-app-credentials.sh. A person makes it in Proxmox.
MANUAL = {"PROXMOX_API_TOKEN_SECRET"}


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


def split_missing(missing):
    generated = [name for name in missing if name not in MANUAL]
    manual = [name for name in missing if name in MANUAL]
    return generated, manual


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


def ensure_secrets(env, dry):
    """Check names first. Fill the ones gen-app-credentials.sh creates, then check again.

    A missing Proxmox API token is printed and stops the run. This does not
    loop: one fill either clears the generated names or it does not.
    """
    try:
        missing = missing_secrets(env)
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"STOP: could not list GitHub secret names ({type(exc).__name__})", file=sys.stderr)
        return 1
    if not missing:
        print("secrets: none missing")
        return 0
    print("missing: " + " ".join(missing))
    generated, _manual = split_missing(missing)
    if generated:
        cmd = ["utils/gen-app-credentials.sh", "--env", env, "--all"]
        if dry:
            cmd.append("--dry-run")
            print("would: " + " ".join(cmd))
        else:
            print("+ " + " ".join(cmd))
            result = subprocess.run(cmd, cwd=ROOT)
            if result.returncode != 0:
                return result.returncode
            try:
                missing = missing_secrets(env)
            except (OSError, subprocess.CalledProcessError) as exc:
                print(f"STOP: could not list GitHub secret names ({type(exc).__name__})", file=sys.stderr)
                return 1
            print("missing: " + " ".join(missing) if missing else "secrets: none missing")
    if dry:
        manual = split_missing(missing)[1]
        if manual:
            print("still needs a person: " + " ".join(manual))
            if env == "dev":
                print("create the token in Proxmox, then utils/bootstrap-dev-proxmox.sh --set-token")
            return 1
        return 0
    if not missing:
        return 0
    print("still missing: " + " ".join(missing))
    if "PROXMOX_API_TOKEN_SECRET" in missing and env == "dev":
        print("create the token in Proxmox, then utils/bootstrap-dev-proxmox.sh --set-token")
    elif "PROXMOX_API_TOKEN_SECRET" in missing:
        print("create the token in Proxmox and store PROXMOX_API_TOKEN_SECRET in the prod environment")
    return 1


def prepare(env, dry):
    code = ensure_secrets(env, dry)
    if code != 0:
        return code
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
    generated, manual = split_missing(list(REQUIRED))
    assert manual == ["PROXMOX_API_TOKEN_SECRET"]
    assert "POSTGRES_PASSWORD" in generated and "PROXMOX_API_TOKEN_SECRET" not in generated
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
