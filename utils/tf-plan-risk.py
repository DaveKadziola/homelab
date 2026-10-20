#!/usr/bin/env python3
"""Classify a Terraform plan for the prod risk gate (Infra Apply Prod).

  terraform show -json tfplan > plan.json
  utils/tf-plan-risk.py plan.json >> "$GITHUB_OUTPUT"
  utils/tf-plan-risk.py --self-test

Prints `risky=true|false` and `digest=<sha256>` on stdout and one line per change (address and
actions, never values) on stderr. Safe: no-op and read; create or update of a
proxmox_virtual_environment_file. Everything else is risky: any change to a VM (an update can
reboot it), every delete or replace - also of the cloud_config snippet, which Proxmox hands to the
VM at each boot although Terraform ignores `initialization` -, imports, forget, and every resource
type not named here.
The digest covers everything the verdict reads, so an equal digest means an equal verdict; the
apply job re-plans and refuses to apply when the digest differs from the one that was gated.
The plan JSON holds secrets in plain text: this script never prints anything from it but
addresses, types and actions, and error messages name only the exception class.
Exit code: 0 classified, 1 self-test failed, 2 unreadable input.
"""
import argparse
import hashlib
import json
import sys

FILE = "proxmox_virtual_environment_file"


def reason(rc):
    """None when the change is safe, otherwise a short reason."""
    change = rc["change"]
    acts = change["actions"]
    if change.get("importing"):
        return "import"
    if acts in (["no-op"], ["read"]):
        return None
    if rc["type"] == FILE and acts in (["create"], ["update"]):
        return None
    return "/".join(acts)


def digest(changes):
    rows = sorted([rc["address"], rc.get("deposed") or "", rc["change"]["actions"],
                   bool(rc["change"].get("importing"))] for rc in changes)
    return hashlib.sha256(json.dumps(rows).encode()).hexdigest()


def classify(plan):
    if not str(plan.get("format_version", "")).startswith("1.") or plan.get("errored"):
        raise ValueError("not a complete plan")
    changes = plan.get("resource_changes") or []
    lines, risky = [], False
    for rc in changes:
        acts = rc["change"]["actions"]
        why = reason(rc)
        if why is None and acts == ["no-op"]:
            continue
        risky = risky or why is not None
        lines.append(f"{'RISKY' if why else 'safe '} {'/'.join(acts):<14} {rc['address']}"
                     + (f" (deposed {rc['deposed']})" if rc.get("deposed") else ""))
    return risky, digest(changes), lines


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("plan", nargs="?", help="output of `terraform show -json <planfile>`")
    parser.add_argument("--self-test", action="store_true", help="test the classifier, no plan")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    if not args.plan:
        parser.error("plan JSON file is required")
    try:
        with open(args.plan) as f:
            risky, dig, lines = classify(json.load(f))
    except (OSError, ValueError, KeyError, TypeError) as e:
        print(f"error: cannot read the plan ({type(e).__name__})", file=sys.stderr)
        return 2
    for line in lines or ["no changes"]:
        print(line, file=sys.stderr)
    print(f"risky={'true' if risky else 'false'}")
    print(f"digest={dig}")
    return 0


def self_test():
    def rc(address, acts, importing=False, deposed=None):
        type_, name = address.split("[")[0].split(".")[-2:]
        r = {"address": address, "type": type_, "name": name, "change": {"actions": acts}}
        if importing:
            r["change"]["importing"] = {"id": "x"}
        if deposed:
            r["deposed"] = deposed
        return r

    def verdict(*changes):
        return classify({"format_version": "1.2", "resource_changes": list(changes)})[0]

    vm = 'proxmox_virtual_environment_vm.vm["nas"]'
    snippet = 'proxmox_virtual_environment_file.cloud_config["apps"]'
    image = 'proxmox_virtual_environment_file.vm_image["apps"]'
    assert verdict() is False
    assert verdict(rc(vm, ["no-op"]), rc(snippet, ["no-op"])) is False
    assert verdict(rc(snippet, ["delete", "create"])) is True
    assert verdict(rc(snippet, ["create", "delete"])) is True
    assert verdict(rc(snippet, ["delete"])) is True
    assert verdict(rc(image, ["create"])) is False
    assert verdict(rc(image, ["update"])) is False
    assert verdict(rc(image, ["delete", "create"])) is True
    assert verdict(rc(vm, ["update"])) is True
    assert verdict(rc(vm, ["create"])) is True
    assert verdict(rc("proxmox_virtual_environment_network_linux_bridge.vmbr0[0]", ["create"])) is True
    assert verdict(rc("proxmox_virtual_environment_dns.node_dns_setup[0]", ["update"])) is True
    assert verdict(rc("random_password.x", ["create"])) is True
    assert verdict(rc(vm, ["forget"])) is True
    assert verdict(rc(vm, ["no-op"], importing=True)) is True
    assert verdict(rc("data.http.x", ["read"])) is False
    assert verdict(rc(snippet, ["delete"], deposed="abc")) is True

    a = [rc(vm, ["no-op"]), rc(snippet, ["delete", "create"])]
    assert digest(a) == digest(list(reversed(a)))
    assert digest(a) != digest([rc(vm, ["update"]), rc(snippet, ["delete", "create"])])
    assert digest(a) != digest([rc(vm, ["no-op"], importing=True), rc(snippet, ["delete", "create"])])
    risky, _, lines = classify({"format_version": "1.2", "resource_changes": a})
    assert risky is True and lines == ['RISKY delete/create  ' + snippet], lines

    for bad in ({"format_version": "0.1"}, {"format_version": "1.2", "errored": True}, {}):
        try:
            classify(bad)
        except ValueError:
            continue
        raise AssertionError(f"accepted {bad}")

    import os
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "plan.json")
        with open(p, "w") as f:
            f.write("{not json")
        assert main([p]) == 2
        with open(p, "w") as f:
            json.dump({"format_version": "1.2", "resource_changes": [rc(vm, ["update"])]}, f)
        assert main([p]) == 0
    print("self-test ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
