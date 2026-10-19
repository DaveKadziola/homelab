#!/usr/bin/env python3
"""Store secrets from the laptop cache in Bitwarden, or queue them while the vault is locked.

Each value in ~/.homelab-secrets/<env>/<NAME> becomes the Secure Note homelab/<NAME>/<env> in
folder homelab. A value never goes into a process argument or environment: bw gets the encoded
item on stdin. An unchanged note is not written again.

Usage:
  utils/bw-store.py --env dev NAME [NAME ...]   store these cache values (the generators call this)
  printf '%s' "$v" | utils/bw-store.py --env prod --stdin NAME
                                                 write the cache file (mode 600) first, then store
  utils/bw-store.py --pending                    store what was queued while the vault was locked
  utils/bw-store.py --env dev|prod|prod-plan|all every cache value of the environment(s)
  add --dry-run to print the actions without writing; --self-test runs the built-in checks

Bitwarden is used when it is unlocked in the same shell (export BW_SESSION="$(bw unlock --raw)").
When it is locked, bw is missing or a write fails, the names (never the values) go to
~/.homelab-secrets/.bw-pending and one line says so; NAME mode then still exits 0, so a
generator never fails on a locked vault.
Exit code: 0 ok or queued, 1 a write failed, 2 usage error or vault locked in --pending/--env mode.
"""
import argparse
import base64
import contextlib
import fcntl
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

CACHE = Path.home() / ".homelab-secrets"
QUEUE = CACHE / ".bw-pending"
FOLDER = "homelab"
ENVS = ("dev", "prod", "prod-plan")
NAME_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")
FLUSH_HINT = 'export BW_SESSION="$(bw unlock --raw)" && utils/bw-store.py --pending'


def bw_json(args, stdin=None):
    # --nointeraction: a locked vault must fail, never wait for a master password prompt.
    res = subprocess.run(["bw", "--nointeraction", *args], input=stdin, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"bw {args[0]} failed: {res.stderr.strip()[:200]}")
    out = res.stdout.strip()
    return json.loads(out) if out.startswith(("{", "[")) else out


def encode(obj):
    # Same as `bw encode` (base64 of the JSON), without one more bw process per write.
    return base64.b64encode(json.dumps(obj).encode()).decode()


def bw_problem():
    """None when the vault is unlocked here, else why not."""
    if not os.environ.get("BW_SESSION"):
        return "BW_SESSION is unset"
    try:
        status = bw_json(["status"])
    except (OSError, RuntimeError, ValueError) as exc:
        return f"bw is not usable ({exc.__class__.__name__})"
    status = status.get("status") if isinstance(status, dict) else None
    return None if status == "unlocked" else f"the vault is {status or 'in an unknown state'}"


def folder_id(create):
    for f in bw_json(["list", "folders", "--search", FOLDER]):
        if f.get("name") == FOLDER:
            return f["id"]
    return bw_json(["create", "folder"], stdin=encode({"name": FOLDER}))["id"] if create else None


def vault_items():
    items = {}
    for item in bw_json(["list", "items", "--search", "homelab/"]):
        items.setdefault(item.get("name"), item)
    return items


def plan(existing, item_name, value, folder):
    """(action, item to send): create, update or unchanged."""
    if existing is None:
        return "create", {"organizationId": None, "collectionIds": None, "folderId": folder, "type": 2,
                          "name": item_name, "notes": value, "favorite": False, "fields": [],
                          "login": None, "secureNote": {"type": 0}, "card": None, "identity": None,
                          "reprompt": 0}
    if existing.get("notes") == value and existing.get("folderId") == folder:
        return "unchanged", None
    return "update", dict(existing, notes=value, folderId=folder)


def read_cache(env, name):
    path = CACHE / env / name
    # Same trimming as the old shell sync ($(cat file)), so notes written by it compare equal.
    return path.read_text(encoding="utf-8").rstrip("\n") if path.is_file() else ""


def write_cache(env, name, value):
    path = CACHE / env / name
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w", encoding="utf-8") as f:
        f.write(value)
    os.chmod(path, 0o600)


def queue_read():
    try:
        lines = QUEUE.read_text(encoding="utf-8").split()
    except FileNotFoundError:
        return set()
    pairs = {tuple(reversed(line.rsplit("/", 1))) for line in lines if "/" in line}
    # The file can be edited by hand; a bad line must not become a path outside the cache.
    return {(e, n) for e, n in pairs if e in ENVS and NAME_RE.match(n)}


def queue_write(pairs):
    CACHE.mkdir(mode=0o700, parents=True, exist_ok=True)
    tmp = QUEUE.with_name(QUEUE.name + ".tmp")
    with os.fdopen(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w", encoding="utf-8") as f:
        f.write("".join(f"{n}/{e}\n" for e, n in sorted(pairs)))
    os.replace(tmp, QUEUE)


def queue_update(add=(), remove=()):
    CACHE.mkdir(mode=0o700, parents=True, exist_ok=True)
    lock = os.open(CACHE, os.O_RDONLY)
    try:
        # Two generators can finish at once; without the lock one drops the other's names.
        fcntl.flock(lock, fcntl.LOCK_EX)
        old = queue_read()
        new = (old - set(remove)) | set(add)
        if new != old:
            queue_write(new)
        return new
    finally:
        os.close(lock)


def store(pairs, dry_run, given=None):
    """Upsert each (env, name) from `given` or the cache. Returns the pairs that failed."""
    bw_json(["sync"])
    folder = folder_id(create=not dry_run)
    items = vault_items()
    failed = []
    for env, name in pairs:
        item_name = f"homelab/{name}/{env}"
        value = (given or {}).get((env, name)) or read_cache(env, name)
        if not value:
            print(f"  {item_name}: no cache value - skipped")
            continue
        action, item = plan(items.get(item_name), item_name, value, folder)
        if action == "unchanged" or dry_run:
            print(f"  {item_name}: {action}{' (dry run)' if action != 'unchanged' else ''}")
            continue
        try:
            if action == "create":
                bw_json(["create", "item"], stdin=encode(item))
            else:
                bw_json(["edit", "item", item["id"]], stdin=encode(item))
        except RuntimeError as exc:
            print(f"  {item_name}: FAILED {exc}", file=sys.stderr)
            failed.append((env, name))
            continue
        print(f"  {item_name}: {action}d")
    return failed


def cache_pairs(envs):
    pairs = []
    for env in envs:
        directory = CACHE / env
        if not directory.is_dir():
            print(f"{env}: no cache at {directory} - skipped")
            continue
        pairs += [(env, p.name) for p in sorted(directory.iterdir()) if p.is_file() and NAME_RE.match(p.name)]
    return pairs


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("names", nargs="*", metavar="NAME")
    parser.add_argument("--env", choices=[*ENVS, "all"])
    parser.add_argument("--stdin", action="store_true", help="value of the single NAME on stdin")
    parser.add_argument("--pending", action="store_true", help="store the queued names")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)

    # Everything created here holds a value or a secret name; a first --stdin write also creates
    # ~/.homelab-secrets itself, which mkdir(parents=True) would leave at the default umask.
    os.umask(0o077)
    if args.self_test:
        return self_test()
    bad = [n for n in args.names if not NAME_RE.match(n)]
    if bad or (args.pending and (args.env or args.names)) or (not args.pending and not args.env) \
            or (args.names and args.env == "all") or (args.stdin and len(args.names) != 1):
        parser.error("use --env ENV NAME..., --env ENV --stdin NAME, --env ENV|all, or --pending"
                     + (f"; bad name: {', '.join(bad)}" if bad else ""))

    # NAME mode is called by generators: a locked vault or a failed write queues, never fails them.
    hook = bool(args.names)
    given = {}
    if hook:
        pairs = [(args.env, n) for n in args.names]
        if args.stdin:
            value = sys.stdin.read()
            if not value.strip():
                print("error: empty value on stdin", file=sys.stderr)
                return 2
            # A dry run leaves the cache as it is, so the plan must compare the new value.
            given[pairs[0]] = value.rstrip("\n")
            if not args.dry_run:
                write_cache(args.env, args.names[0], value)
            print(f"cache {CACHE / args.env / args.names[0]}: {'would write' if args.dry_run else 'written'}")
    elif args.pending:
        pairs = sorted(queue_read())
        if not pairs:
            print("nothing pending")
            return 0
    else:
        pairs = cache_pairs(ENVS if args.env == "all" else [args.env])

    problem = bw_problem()
    if problem and not hook:
        print(f"error: {problem}. Run: export BW_SESSION=\"$(bw unlock --raw)\"", file=sys.stderr)
        return 2
    failed = pairs
    if not problem:
        if not hook:
            print(f"{len(pairs)} secret(s) -> Bitwarden folder {FOLDER}{', dry run' if args.dry_run else ''}")
        try:
            failed = store(pairs, args.dry_run, given)
        except Exception as exc:  # any failure must queue the names, not lose them
            # Only the class of an unexpected error: a decode error message can quote a value's bytes.
            problem = str(exc) if isinstance(exc, RuntimeError) else exc.__class__.__name__
    if not args.dry_run:
        queue_update(add=failed, remove=pairs)
    if failed:
        names = " ".join(f"homelab/{n}/{e}" for e, n in failed)
        print(f"Bitwarden: {problem or 'write failed'} - {'would queue' if args.dry_run else 'queued'} "
              f"{names}; to store later: {FLUSH_HINT}", file=sys.stderr)
    return 0 if hook or not failed else 1


def self_test():
    """Assert-based checks against a fake bw in a temporary cache; the real vault is never called."""
    global CACHE, QUEUE, bw_json
    saved = (CACHE, QUEUE, bw_json, os.environ.get("BW_SESSION"))
    tmp = Path(tempfile.mkdtemp())
    CACHE, QUEUE = tmp, tmp / ".bw-pending"
    vault = {"status": "unlocked", "folders": [], "items": []}
    calls = []

    def fake_bw(args, stdin=None):
        calls.append(list(args))
        if args[0] == "status":
            return {"status": vault["status"]}
        if args[0] == "sync":
            return "Syncing complete."
        if args[:2] in (["list", "folders"], ["list", "items"]):
            return json.loads(json.dumps(vault[args[1]]))
        body = json.loads(base64.b64decode(stdin))
        if args[:2] == ["create", "folder"]:
            vault["folders"].append(dict(body, id="folder-1"))
            return vault["folders"][-1]
        if args[:2] == ["create", "item"]:
            vault["items"].append(dict(body, id=f"item-{len(vault['items'])}"))
            return vault["items"][-1]
        if args[:2] == ["edit", "item"]:
            if vault.get("fail_edit"):
                raise RuntimeError("bw edit failed: test")
            vault["items"] = [body if i["id"] == args[2] else i for i in vault["items"]]
            return body
        raise AssertionError(f"unexpected bw call {args}")

    def run(argv, stdin=""):
        out, err = io.StringIO(), io.StringIO()
        sys.stdin = io.StringIO(stdin)
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = main(argv)
        return rc, out.getvalue(), err.getvalue()

    try:
        bw_json = fake_bw
        # Item JSON and the upsert decision.
        action, item = plan(None, "homelab/A/dev", "v1", "F")
        assert action == "create" and item["type"] == 2 and item["secureNote"] == {"type": 0}
        assert item["name"] == "homelab/A/dev" and item["notes"] == "v1" and item["folderId"] == "F"
        assert plan({"id": "1", "notes": "v1", "folderId": "F"}, "homelab/A/dev", "v1", "F") == ("unchanged", None)
        action, item = plan({"id": "1", "notes": "v0", "folderId": "G", "x": 1}, "homelab/A/dev", "v1", "F")
        assert action == "update" and item == {"id": "1", "notes": "v1", "folderId": "F", "x": 1}
        assert json.loads(base64.b64decode(encode({"a": "ż"}))) == {"a": "ż"}

        # Queue: dedupe, remove, bad lines ignored.
        queue_update(add=[("dev", "A"), ("dev", "A"), ("prod-plan", "B")])
        assert queue_read() == {("dev", "A"), ("prod-plan", "B")}
        assert QUEUE.read_text() == "A/dev\nB/prod-plan\n" and QUEUE.stat().st_mode & 0o777 == 0o600
        assert queue_update(remove=[("dev", "A")]) == {("prod-plan", "B")}
        QUEUE.write_text("B/prod-plan\nB/prod-plan\n../../x/dev\nC/test\nlower/dev\n")
        assert queue_read() == {("prod-plan", "B")}
        queue_write(set())

        # Locked: names are queued, the caller gets 0, bw is not touched without BW_SESSION.
        os.environ.pop("BW_SESSION", None)
        rc, out, err = run(["--env", "dev", "--stdin", "A"], stdin="secret-a\n")
        assert rc == 0 and calls == [] and "queued homelab/A/dev" in err and "--pending" in err
        assert (tmp / "dev" / "A").read_text() == "secret-a\n" and (tmp / "dev" / "A").stat().st_mode & 0o777 == 0o600
        assert queue_read() == {("dev", "A")}
        os.environ["BW_SESSION"] = "fake"
        vault["status"] = "locked"
        assert run(["--pending"])[0] == 2 and queue_read() == {("dev", "A")}

        # Unlocked: the queue is flushed, the folder is created once, a re-run writes nothing.
        vault["status"] = "unlocked"
        (tmp / "dev" / "B").write_text("secret-b")
        assert run(["--pending"])[0] == 0 and queue_read() == set()
        assert [i["notes"] for i in vault["items"]] == ["secret-a"] and vault["items"][0]["folderId"] == "folder-1"
        assert run(["--env", "dev", "A", "B"])[0] == 0 and len(vault["items"]) == 2
        calls.clear()
        rc, out, _ = run(["--env", "all"])
        assert rc == 0 and out.count("unchanged") == 2 and "prod: no cache" in out
        assert not [c for c in calls if c[0] in ("create", "edit")] and len(vault["folders"]) == 1

        # A changed value is an update of the same item; dry run writes nothing.
        (tmp / "dev" / "B").write_text("secret-b2\n")
        rc, out, _ = run(["--env", "dev", "--dry-run"])
        assert rc == 0 and "update (dry run)" in out and vault["items"][1]["notes"] == "secret-b"
        assert run(["--env", "dev", "B"])[0] == 0 and vault["items"][1]["notes"] == "secret-b2"
        assert len(vault["items"]) == 2 and vault["items"][1]["id"] == "item-1"

        # --stdin --dry-run plans with the given value, not the old cache file, and writes nothing.
        assert "unchanged" in run(["--env", "dev", "--stdin", "B", "--dry-run"], stdin="secret-b2\n")[1]
        rc, out, _ = run(["--env", "dev", "--stdin", "B", "--dry-run"], stdin="secret-b3")
        assert rc == 0 and "update (dry run)" in out and (tmp / "dev" / "B").read_text() == "secret-b2\n"
        assert vault["items"][1]["notes"] == "secret-b2" and queue_read() == set()

        # A failed write is queued, never lost: 0 for a generator, 1 for an operator sync.
        vault["fail_edit"] = True
        (tmp / "dev" / "A").write_text("secret-a2")
        rc, _, err = run(["--env", "dev", "A"])
        assert rc == 0 and "queued homelab/A/dev" in err and queue_read() == {("dev", "A")}
        assert run(["--pending"])[0] == 1 and queue_read() == {("dev", "A")}
        vault["fail_edit"] = False
        assert run(["--pending"])[0] == 0 and queue_read() == set() and vault["items"][0]["notes"] == "secret-a2"

        # Unexpected bw output is queued the same way, and only the error class is printed.
        folders, vault["folders"] = vault["folders"], "not a list"
        rc, _, err = run(["--env", "dev", "B"])
        assert rc == 0 and "AttributeError - queued homelab/B/dev" in err and queue_read() == {("dev", "B")}
        assert run(["--pending"])[0] == 1 and queue_read() == {("dev", "B")}
        vault["folders"] = folders
        assert run(["--pending"])[0] == 0 and queue_read() == set()

        # No value ever reached a bw argument.
        assert not [c for c in calls if any("secret-" in a for a in c)]
        for bad in (["--env", "all", "A"], ["--pending", "--env", "dev"], ["--env", "dev", "../A"], []):
            try:
                run(bad)
            except SystemExit as exc:
                assert exc.code == 2
            else:
                raise AssertionError(f"accepted {bad}")
    finally:
        sys.stdin = sys.__stdin__
        CACHE, QUEUE, bw_json = saved[:3]
        if saved[3] is None:
            os.environ.pop("BW_SESSION", None)
        else:
            os.environ["BW_SESSION"] = saved[3]
        shutil.rmtree(tmp)
    print("self-test: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
