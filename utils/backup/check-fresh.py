#!/usr/bin/env python3
"""Check the age of every backup stream and report it to its Uptime Kuma push monitor (F10-A).

  check-fresh.py --env prod [--dry-run]
  check-fresh.py --self-test

Runs on the NAS (homelab-backup-check.timer): the backup root there is <export_root>/backups,
which holds what the apps host writes over NFS, what run-nas.sh pulls and the Proxmox dumps. For
each stream of config/monitoring.yml `backups` enabled for the env, the newest file matching `glob`
must be younger than `max_age_hours`. Each result is pushed to
<kuma_url>/api/push/<token>?status=up|down&msg=... (token = first 24 hex characters of
sha256("<KUMA_PUSH_SECRET>:<stream>")), so a stale stream alerts at once and a silent NAS alerts
when the push monitor's heartbeat runs out. --dry-run prints and pushes nothing.
Config: HOMELAB_CONFIG_DIR (default <repo>/config). Secret KUMA_PUSH_SECRET: environment, else
$HOMELAB_SECRETS_DIR/<env>/KUMA_PUSH_SECRET. Never printed.
Exit code: 0 every stream fresh, 1 a stream stale or a push failed, 2 usage or missing config.
"""
import argparse
import hashlib
import os
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def push_token(secret, stream):
    return hashlib.sha256(f"{secret}:{stream}".encode()).hexdigest()[:24]


def newest(base, pattern):
    """(path, mtime) of the newest file matching pattern under base, or (None, None)."""
    best = (None, None)
    for path in Path(base).glob(pattern):
        if path.is_file():
            mtime = path.stat().st_mtime
            if best[1] is None or mtime > best[1]:
                best = (path, mtime)
    return best


def verdicts(streams, env, base, now):
    """[(stream, ok, message)] for the streams enabled in env."""
    out = []
    for s in streams:
        if env not in s.get("envs", []):
            continue
        path, mtime = newest(base, s["glob"])
        if path is None:
            out.append((s["stream"], False, f"no file matches {s['glob']}"))
            continue
        hours = (now - mtime) / 3600
        ok = hours <= s["max_age_hours"]
        out.append((s["stream"], ok, f"{path.name} is {hours:.1f} h old (max {s['max_age_hours']} h)"))
    return out


def secret(env, name):
    if os.environ.get(name):
        return os.environ[name]
    base = Path(os.environ.get("HOMELAB_SECRETS_DIR", Path.home() / ".homelab-secrets"))
    for path in (base / env / name, base / name):
        if path.is_file():
            return path.read_text().strip()
    return None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--env", choices=["dev", "prod"])
    parser.add_argument("--dry-run", action="store_true", help="print the verdicts, push nothing")
    parser.add_argument("--self-test", action="store_true", help="test the age logic, no NAS")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    if not args.env:
        parser.error("--env dev|prod is required")
    import yaml  # noqa: PLC0415 - not needed by the self-test
    config = Path(os.environ.get("HOMELAB_CONFIG_DIR", ROOT / "config"))
    mon = yaml.safe_load(open(config / "monitoring.yml"))
    st = yaml.safe_load(open(config / "storage.yml"))["environments"][args.env]
    base = st["export_root"].rstrip("/") + "/backups"
    kuma = mon["environments"][args.env]["kuma_url"].rstrip("/")
    key = secret(args.env, "KUMA_PUSH_SECRET")
    if not key and not args.dry_run:
        print("error: KUMA_PUSH_SECRET is not in the environment or the secret cache", file=sys.stderr)
        return 2
    rc = 0
    for stream, ok, msg in verdicts(mon["backups"], args.env, base, time.time()):
        print(f"{'ok   ' if ok else 'STALE'} {stream:<20} {msg}")
        rc = rc if ok else 1
        if args.dry_run:
            continue
        query = urllib.parse.urlencode({"status": "up" if ok else "down", "msg": msg})
        url = f"{kuma}/api/push/{push_token(key, stream)}?{query}"
        try:
            urllib.request.urlopen(url, timeout=20).read()
        except OSError as e:
            print(f"push {stream}: failed ({type(e).__name__})", file=sys.stderr)
            rc = 1
    return rc


def self_test():
    import tempfile
    assert push_token("s", "postgres") == hashlib.sha256(b"s:postgres").hexdigest()[:24]
    assert push_token("s", "postgres") != push_token("s", "volumes")
    with tempfile.TemporaryDirectory() as d:
        now = time.time()
        (Path(d) / "postgres").mkdir()
        old, new = Path(d, "postgres", "a.sql.gz"), Path(d, "postgres", "b.sql.gz")
        old.write_text("x")
        new.write_text("y")
        os.utime(old, (now - 50 * 3600, now - 50 * 3600))
        os.utime(new, (now - 2 * 3600, now - 2 * 3600))
        Path(d, ".offsite-ok").write_text("t")
        os.utime(Path(d, ".offsite-ok"), (now - 30 * 3600, now - 30 * 3600))
        streams = [
            {"stream": "postgres", "glob": "postgres/*.sql.gz", "max_age_hours": 26, "envs": ["dev", "prod"]},
            {"stream": "offsite", "glob": ".offsite-ok", "max_age_hours": 26, "envs": ["prod"]},
            {"stream": "vzdump", "glob": "vzdump/dump/*.vma.zst", "max_age_hours": 26, "envs": ["prod"]},
        ]
        v = {s: (ok, m) for s, ok, m in verdicts(streams, "prod", d, now)}
        assert v["postgres"][0] is True and "b.sql.gz" in v["postgres"][1], v
        assert v["offsite"][0] is False, v
        assert v["vzdump"] == (False, "no file matches vzdump/dump/*.vma.zst"), v
        assert [s for s, _, _ in verdicts(streams, "dev", d, now)] == ["postgres"]
    print("self-test ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
