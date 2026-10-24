#!/usr/bin/env python3
"""Make the Proxmox VE host keep a nightly vzdump job of the VMs on an NFS storage of the NAS.

  utils/pve-backup-job.py --env dev --dry-run
  utils/pve-backup-job.py --env prod
  utils/pve-backup-job.py --self-test

Config: config/storage.yml environments.<env> (nas_host, nas_private_root, vzdump: pve_host, vmids,
schedule, enabled) and retention.keep. API: PROXMOX_API_URL (default
https://<vzdump.pve_host>:8006/api2/json), PROXMOX_API_TOKEN_ID, PROXMOX_API_TOKEN_SECRET; on dev
the token defaults to root@pam!terraform with the secret from ~/.homelab-pve-dev-token-secret.
The secret is never printed.
First the storage `nas-backups` (NFS <nas_host>:<nas_private_root>/vzdump, content backup, options
vers=4.2), then the job `homelab-vms` (snapshot, zstd, notes {{guestname}}); both prune to
keep-last=<keep>. Last, PVE must report the storage online, or vzdump would fail on it.
Missing -> created, differing -> only the differing fields updated, equal -> "ok". Stops when the
API's node is not proxmox_node_name of that env, or the storage exists with another type, server
or export. Creating the storage makes PVE mount it: the export must exist on the NAS first.
Exit code: 0 ok or no change, 1 stop or API failure, 2 usage error or missing config/credentials.
"""
import argparse
import io
import json
import os
import re
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORAGE_ID = "nas-backups"
JOB_ID = "homelab-vms"
DEV_TOKEN_ID = "root@pam!terraform"
DEV_SECRET_FILE = Path.home() / ".homelab-pve-dev-token-secret"
# PVE keeps the type, server and export of a mounted storage; changing them is a manual decision.
STORAGE_FIXED = ("type", "server", "export")
# PVE leaves `enabled` out of a job that uses its default.
JOB_DEFAULTS = {"enabled": 1}


class Stop(Exception):
    """A condition the operator has to look at; message is safe to print."""


def node_name(tfvars):
    m = re.search(r'^proxmox_node_name\s*=\s*"([^"]*)"', tfvars, re.M)
    return m.group(1) if m else ""


def desired(env_cfg, keep):
    """(storage, job) fields as POST /storage and POST /cluster/backup take them."""
    vz = env_cfg["vzdump"]
    if not vz["vmids"] or not isinstance(vz["enabled"], bool) or not vz["schedule"]:
        raise ValueError("vzdump needs vmids, schedule and enabled: true|false")
    prune = f"keep-last={int(keep)}"
    storage = {"type": "nfs", "server": env_cfg["nas_host"],
               "export": f"{env_cfg['nas_private_root'].rstrip('/')}/vzdump",
               "content": "backup", "prune-backups": prune,
               # Without vers=4 PVE checks the server with showmount (rpcbind, mountd), which the NAS
               # firewall drops; with it, rpcinfo (TCP 111 from the PVE host) and then TCP 2049.
               "options": "vers=4.2"}
    job = {"schedule": vz["schedule"], "vmid": ",".join(str(int(v)) for v in vz["vmids"]),
           "storage": STORAGE_ID, "mode": "snapshot", "compress": "zstd",
           "enabled": int(vz["enabled"]), "prune-backups": prune, "notes-template": "{{guestname}}"}
    return storage, job


def norm(key, value):
    """Comparable form: PVE answers enabled as 1/0, vmid as "101,102" and prune-backups as a dict
    or a "k=v,k=v" string."""
    if value is None:
        return None
    if isinstance(value, dict):
        value = ",".join(f"{k}={v}" for k, v in value.items())
    if isinstance(value, bool):
        value = int(value)
    if key in ("vmid", "content", "prune-backups"):
        return ",".join(sorted(p.strip() for p in str(value).split(",") if p.strip()))
    return str(value)


def plan(what, want, have, fixed=(), defaults=None):
    """("create", all fields) | ("update", differing fields) | ("ok", []); Stop on a fixed field."""
    if have is None:
        return "create", list(want)
    defaults = defaults or {}
    diff = [k for k in want if norm(k, want[k]) != norm(k, have.get(k, defaults.get(k)))]
    bad = [k for k in diff if k in fixed]
    if bad:
        raise Stop(f"{what} exists with " + ", ".join(f"{k}={have.get(k)} (want {want[k]})" for k in bad)
                   + " - PVE cannot change that in place; fix or remove it by hand")
    return ("update" if diff else "ok"), diff


def pve_message(err):
    """PVE's error text of an HTTPError (no secret in it), one line, at most 200 chars."""
    try:
        doc = json.loads(err.read() or b"{}")
        text = " ".join(str(doc[k]) for k in ("message", "errors") if doc.get(k))
    except (ValueError, OSError, AttributeError):
        text = ""
    return " ".join((text or str(err.reason or "")).split())[:200]


class Api:
    def __init__(self, url, token_id, secret):
        self.url = url.rstrip("/")
        self.auth = f"PVEAPIToken={token_id}={secret}"
        # The PVE host serves a self-signed certificate; terraform/providers.tf has insecure = true.
        self.ctx = ssl.create_default_context()
        self.ctx.check_hostname = False
        self.ctx.verify_mode = ssl.CERT_NONE

    def call(self, method, path, body=None):
        data = None if body is None else urllib.parse.urlencode(body).encode()
        req = urllib.request.Request(self.url + path, data=data, method=method)
        req.add_header("Authorization", self.auth)
        try:
            with urllib.request.urlopen(req, context=self.ctx, timeout=30) as resp:
                return json.loads(resp.read() or b"{}").get("data")
        except urllib.error.HTTPError as e:
            raise Stop(f"{method} {path}: HTTP {e.code} {pve_message(e)}") from None
        except (urllib.error.URLError, OSError) as e:
            raise Stop(f"{method} {path}: {getattr(e, 'reason', e)}") from None


def credentials(env, pve_host):
    url = os.environ.get("PROXMOX_API_URL") or f"https://{pve_host}:8006/api2/json"
    token_id = os.environ.get("PROXMOX_API_TOKEN_ID") or (DEV_TOKEN_ID if env == "dev" else "")
    secret = os.environ.get("PROXMOX_API_TOKEN_SECRET", "")
    if not secret and env == "dev" and DEV_SECRET_FILE.is_file():
        secret = DEV_SECRET_FILE.read_text().strip()
    return url, token_id, secret


def ensure(api, what, want, find, create, update, dry_run, fixed=(), defaults=None):
    """create = (path, {id field}), update = path; prints one line per object."""
    action, fields = plan(what, want, find(), fixed, defaults)
    if action == "ok":
        print(f"ok    {what}")
        return
    print(f"{'would ' if dry_run else ''}{action} {what}: " + ", ".join(f"{k}={want[k]}" for k in fields))
    if dry_run:
        return
    body = {k: want[k] for k in fields}
    if action == "create":
        api.call("POST", create[0], {**create[1], **body})
    else:
        api.call("PUT", update, body)
    if plan(what, want, find(), fixed, defaults)[0] != "ok":
        raise Stop(f"{what} still differs after {action} - check it in the PVE GUI")
    print(f"ok    {what} (read back after {action})")


def check_online(api, node):
    """The mount can still work while PVE reports the storage offline; vzdump then refuses it."""
    status = api.call("GET", f"/nodes/{node}/storage/{STORAGE_ID}/status") or {}
    if not status.get("active"):
        raise Stop(f"storage {STORAGE_ID} is not online on {node} (pvesm status) - vzdump would fail; "
                   "check the NFS export and the NAS host firewall")
    print(f"ok    storage {STORAGE_ID} online")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--env", choices=["dev", "prod"])
    parser.add_argument("--dry-run", action="store_true", help="GET only, print what would change")
    parser.add_argument("--self-test", action="store_true", help="test the comparison logic, no network")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    if not args.env:
        parser.error("--env dev|prod is required")

    import yaml  # noqa: PLC0415 - only needed here; the self-test runs without it
    doc = yaml.safe_load((ROOT / "config" / "storage.yml").read_text(encoding="utf-8"))
    try:
        env_cfg = doc["environments"][args.env]
        want_storage, want_job = desired(env_cfg, doc["retention"]["keep"])
    except (KeyError, TypeError, ValueError) as e:
        print(f"config/storage.yml environments.{args.env}: missing or bad value {e}", file=sys.stderr)
        return 2
    url, token_id, secret = credentials(args.env, env_cfg["vzdump"]["pve_host"])
    if not token_id or not secret:
        where = f" or {DEV_SECRET_FILE}" if args.env == "dev" else ""
        print(f"missing PROXMOX_API_TOKEN_ID or PROXMOX_API_TOKEN_SECRET (environment{where})", file=sys.stderr)
        return 2
    tfvars = (ROOT / "terraform" / "environments" / args.env / "terraform.tfvars").read_text(encoding="utf-8")
    node = node_name(tfvars)
    api = Api(url, token_id, secret)
    try:
        # PROXMOX_API_URL may come from a shell set up for the other env.
        nodes = [n.get("node") for n in api.call("GET", "/nodes") or []]
        if not node or node not in nodes:
            raise Stop(f"{url} has nodes {nodes}, --env {args.env} expects '{node}'")
        # GET /storage/<id> answers HTTP 500 for a missing storage (PVE 8.4), so pick it from the list.
        ensure(api, f"storage {STORAGE_ID}", want_storage,
               lambda: next((s for s in api.call("GET", "/storage") if s.get("storage") == STORAGE_ID), None),
               ("/storage", {"storage": STORAGE_ID}), f"/storage/{STORAGE_ID}", args.dry_run, fixed=STORAGE_FIXED)
        ensure(api, f"backup job {JOB_ID}", want_job,
               lambda: next((j for j in api.call("GET", "/cluster/backup") if j.get("id") == JOB_ID), None),
               ("/cluster/backup", {"id": JOB_ID}), f"/cluster/backup/{JOB_ID}", args.dry_run, defaults=JOB_DEFAULTS)
        if not args.dry_run:
            check_online(api, node)
    except Stop as e:
        print(f"STOP: {e}", file=sys.stderr)
        return 1
    if args.dry_run:
        print("dry run - nothing changed")
    return 0


def self_test():
    tf = '# proxmox_node_name = "x"\nproxmox_node_name   = "dev"\n'
    assert node_name(tf) == "dev" and node_name('# proxmox_node_name = "x"\n') == ""

    env = {"nas_host": "192.168.20.12", "nas_private_root": "/srv/purple/nas-backups/",
           "vzdump": {"pve_host": "192.168.20.20", "vmids": [101, 102], "schedule": "04:30", "enabled": True}}
    st, job = desired(env, 2)
    assert st == {"type": "nfs", "server": "192.168.20.12", "export": "/srv/purple/nas-backups/vzdump",
                  "content": "backup", "prune-backups": "keep-last=2", "options": "vers=4.2"}, st
    assert job["vmid"] == "101,102" and job["enabled"] == 1 and job["storage"] == STORAGE_ID, job
    assert job["prune-backups"] == "keep-last=2" and job["notes-template"] == "{{guestname}}", job
    assert desired({**env, "vzdump": {**env["vzdump"], "enabled": False}}, 2)[1]["enabled"] == 0
    for bad in ({"vmids": []}, {"enabled": "no"}, {"schedule": ""}):
        try:
            desired({**env, "vzdump": {**env["vzdump"], **bad}}, 2)
            raise AssertionError(bad)
        except ValueError:
            pass

    assert norm("enabled", 1) == norm("enabled", True) == norm("enabled", "1") == "1"
    assert norm("vmid", "102, 101") == norm("vmid", "101,102")
    assert norm("prune-backups", {"keep-last": 2}) == norm("prune-backups", "keep-last=2")
    assert norm("prune-backups", {"keep-weekly": "1", "keep-last": 2}) == norm("prune-backups", "keep-last=2,keep-weekly=1")
    assert norm("content", "iso,backup") != norm("content", "backup")

    assert plan("s", st, None) == ("create", list(st))
    have = {**st, "content": "backup", "prune-backups": {"keep-last": 2}, "digest": "x", "storage": STORAGE_ID}
    assert plan("s", st, have, STORAGE_FIXED) == ("ok", [])
    assert plan("s", st, {**have, "content": "backup,iso", "prune-backups": "keep-all=1"},
                STORAGE_FIXED) == ("update", ["content", "prune-backups"])
    for key in ("server", "export", "type"):
        try:
            plan("s", st, {**have, key: "other"}, STORAGE_FIXED)
            raise AssertionError(key)
        except Stop as e:
            assert f"{key}=other" in str(e), e

    pve_job = {"id": JOB_ID, "type": "vzdump", "schedule": "04:30", "vmid": "102,101", "storage": STORAGE_ID,
               "mode": "snapshot", "compress": "zstd", "prune-backups": {"keep-last": "2"},
               "notes-template": "{{guestname}}", "next-run": 1}
    assert plan("j", job, pve_job, defaults=JOB_DEFAULTS) == ("ok", [])  # enabled left out = 1
    assert plan("j", {**job, "enabled": 0}, pve_job, defaults=JOB_DEFAULTS) == ("update", ["enabled"])
    assert plan("j", job, {**pve_job, "enabled": 0}, defaults=JOB_DEFAULTS) == ("update", ["enabled"])
    assert plan("j", job, {**pve_job, "vmid": "101"}, defaults=JOB_DEFAULTS) == ("update", ["vmid"])

    body = io.BytesIO(json.dumps({"data": None, "message": "x" * 300}).encode())
    msg = pve_message(urllib.error.HTTPError("https://h/api2/json/storage", 500, "boom", {}, body))
    assert msg == "x" * 200, msg
    assert pve_message(urllib.error.HTTPError("u", 401, "no ticket", {}, io.BytesIO(b"<html>"))) == "no ticket"
    print("self-test ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
