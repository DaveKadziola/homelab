#!/usr/bin/env python3
"""Generate secrets and store them in Bitwarden, the GitHub Environment and the laptop cache.

Bitwarden is written first and is the copy to trust; GitHub and ~/.homelab-secrets/<env>/
follow. No staging file, no value on stdout or in process arguments.

Modes:
  --generate          new random values for the secrets in config/identities.yml
                      (prod before it exists, or DEV right before a rebuild - rotating a
                      running DEV breaks its databases)
  --vault-from-cache  keep today's values from ~/.homelab-secrets/<env>/ and only write
                      them to Bitwarden (DEV as it runs now)

Usage (Bitwarden must be unlocked in the same shell):
  export BW_SESSION="$(bw unlock --raw)"
  utils/rotate-secrets.py --env prod --generate                      # dry run
  utils/rotate-secrets.py --env prod --generate --only POSTGRES_PASSWORD --apply
  utils/rotate-secrets.py --env prod --generate --apply
  utils/rotate-secrets.py --env dev --vault-from-cache --apply

Secrets issued by an app (HA_TOKEN) are never generated here.
Exit code: 0 ok, 1 a write failed, 2 usage or environment error.
"""
import argparse
import json
import os
import secrets
import string
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOME = Path.home()
FOLDER = "homelab"
ALNUM = string.ascii_letters + string.digits


def run(cmd, stdin=None):
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True)


def declared_secrets(env):
    try:
        import yaml
    except ImportError:
        print("error: python3-yaml is required", file=sys.stderr)
        sys.exit(2)
    doc = yaml.safe_load((ROOT / "config" / "identities.yml").read_text(encoding="utf-8"))
    out = {}
    for item in (doc.get("accounts") or []) + (doc.get("service_secrets") or []):
        name = item.get("secret") or item.get("name")
        if not name or env not in (item.get("envs") or []) or item.get("issued_by"):
            continue
        out[name] = item.get("format", "password")
    return out


def generate(fmt):
    if fmt == "hex64":
        return secrets.token_hex(32)
    return "".join(secrets.choice(ALNUM) for _ in range(32))


def bw_json(args, stdin=None):
    # --nointeraction: a locked vault must fail, never wait for a master password prompt.
    res = run(["bw", "--nointeraction", *args], stdin=stdin)
    if res.returncode != 0:
        raise RuntimeError(f"bw {args[0]} failed: {res.stderr.strip()[:200]}")
    out = res.stdout.strip()
    return json.loads(out) if out.startswith(("{", "[")) else out


def bw_ready():
    status = json.loads(run(["bw", "--nointeraction", "status"]).stdout or "{}").get("status")
    return status == "unlocked" and bool(os.environ.get("BW_SESSION"))


def bw_folder_id():
    folders = bw_json(["list", "folders", "--search", FOLDER])
    for f in folders:
        if f.get("name") == FOLDER:
            return f["id"]
    created = bw_json(["create", "folder"], stdin=bw_json(["encode"], stdin=json.dumps({"name": FOLDER})))
    return created["id"]


def bw_find(item_name):
    for item in bw_json(["list", "items", "--search", item_name]):
        if item.get("name") == item_name:
            return item
    return None


def bw_store(item_name, value, folder_id):
    item = bw_find(item_name)
    if item:
        item["notes"] = value
        encoded = bw_json(["encode"], stdin=json.dumps(item))
        bw_json(["edit", "item", item["id"]], stdin=encoded)
        return "updated"
    note = {"organizationId": None, "collectionIds": None, "folderId": folder_id, "type": 2,
            "name": item_name, "notes": value, "favorite": False, "fields": [], "login": None,
            "secureNote": {"type": 0}, "card": None, "identity": None, "reprompt": 0}
    encoded = bw_json(["encode"], stdin=json.dumps(note))
    bw_json(["create", "item"], stdin=encoded)
    return "created"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--env", required=True, choices=["dev", "prod"])
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--generate", action="store_true")
    mode.add_argument("--vault-from-cache", action="store_true")
    parser.add_argument("--only", help="comma-separated secret names")
    parser.add_argument("--repo", default="DaveKadziola/homelab")
    parser.add_argument("--apply", action="store_true", help="write (default: dry run)")
    args = parser.parse_args()

    declared = declared_secrets(args.env)
    cache = HOME / ".homelab-secrets" / args.env
    names = sorted(declared)
    if args.only:
        names = [n.strip() for n in args.only.split(",") if n.strip()]
        unknown = [n for n in names if n not in declared]
        if unknown:
            print(f"error: not generatable here (not declared, or issued by an app): {', '.join(unknown)}",
                  file=sys.stderr)
            return 2
    if args.vault_from_cache:
        missing = [n for n in names if not (cache / n).is_file()]
        if missing:
            print(f"error: no cache value for: {', '.join(missing)}", file=sys.stderr)
            return 2

    what = "new random value -> Bitwarden, GitHub, cache" if args.generate else "cache value -> Bitwarden"
    print(f"env {args.env}: {len(names)} secret(s), {what}, {'APPLY' if args.apply else 'dry run'}")
    for n in names:
        print(f"  homelab/{n}/{args.env}")
    if not args.apply:
        print("dry run - nothing written. Unlock Bitwarden (export BW_SESSION=...) and add --apply.")
        return 0
    if not bw_ready():
        print("error: Bitwarden is locked here. Run: export BW_SESSION=\"$(bw unlock --raw)\"", file=sys.stderr)
        return 2

    run(["bw", "--nointeraction", "sync"])
    folder_id = bw_folder_id()
    cache.mkdir(parents=True, exist_ok=True)
    os.chmod(cache, 0o700)
    failed = []
    for n in names:
        item_name = f"homelab/{n}/{args.env}"
        value = generate(declared[n]) if args.generate else (cache / n).read_text(encoding="utf-8").rstrip("\n")
        try:
            action = bw_store(item_name, value, folder_id)
        except RuntimeError as exc:
            failed.append(f"{n}: Bitwarden: {exc}")
            continue
        steps = [f"bitwarden {action}"]
        if args.generate:
            res = run(["gh", "secret", "set", n, "--env", args.env, "--repo", args.repo], stdin=value)
            if res.returncode != 0:
                failed.append(f"{n}: GitHub: {res.stderr.strip()[:200]} (Bitwarden already has the new value)")
                continue
            path = cache / n
            path.write_text(value, encoding="utf-8")
            os.chmod(path, 0o600)
            steps += ["github set", "cache written"]
        del value
        print(f"  {item_name}: {', '.join(steps)}")
    run(["bw", "--nointeraction", "sync"])
    print(f"done: {len(names) - len(failed)}/{len(names)}")
    for f in failed:
        print(f"FAILED {f}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
