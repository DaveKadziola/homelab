#!/usr/bin/env python3
"""Keep one Immich external library per photos user and scan them (decision 2026-10-23).

    IMMICH_TOKEN=<admin token> immich_libraries.py <api base> <email>=<import path> [...]
    immich_libraries.py --self-test

Each pair names a user by email and that user's folder, e.g. admin@x=/external/photos/admin.
A library already on that path is kept. A library on the old shared root /external/photos is
moved to its owner's folder instead of getting a new one, so its photos are
imported again rather than twice. Every other pair gets a new library owned by that user. Each
library on a wanted path is then scanned. Library endpoints are admin-only in Immich v3.3.3.
Prints one line per action and never the token. Exit code: 0 done, 1 self-test or API failed.
"""
import json
import os
import sys
import urllib.request

LEGACY_ROOT = "/external/photos"


def plan(libraries, user_ids, wanted):
    """Actions for wanted [(email, path)]: ('keep'|'move', lib id, path) or ('create', owner id, path)."""
    actions = []
    for email, path in wanted:
        lib = next((l for l in libraries if path in l.get("importPaths", [])), None)
        if lib is None and email in user_ids:
            lib = next((l for l in libraries if l.get("importPaths") == [LEGACY_ROOT]
                        and l.get("ownerId") == user_ids[email]), None)
            if lib is not None:
                actions.append(("move", lib["id"], path))
                continue
        if lib is not None:
            actions.append(("keep", lib["id"], path))
        elif email in user_ids:
            actions.append(("create", user_ids[email], path))
        else:
            actions.append(("missing-user", email, path))
    return actions


def call(base, token, method, path, body=None):
    req = urllib.request.Request(base.rstrip("/") + path, method=method,
                                 data=None if body is None else json.dumps(body).encode(),
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read()
        return json.loads(raw) if raw else None


def main(argv):
    if argv[1:] == ["--self-test"]:
        return self_test()
    base, pairs = argv[1], [a.split("=", 1) for a in argv[2:]]
    token = os.environ["IMMICH_TOKEN"]
    users = {u["email"]: u["id"] for u in call(base, token, "GET", "/admin/users")}
    for action, ref, path in plan(call(base, token, "GET", "/libraries"), users, [tuple(p) for p in pairs]):
        if action == "missing-user":
            print(f"no Immich user {ref} - library {path} skipped")
            continue
        if action == "move":
            call(base, token, "PUT", f"/libraries/{ref}", {"importPaths": [path]})
            lib_id = ref
        elif action == "create":
            lib_id = call(base, token, "POST", "/libraries",
                          {"ownerId": ref, "name": f"NAS photos ({path.rsplit('/', 1)[-1]})", "importPaths": [path]})["id"]
        else:
            lib_id = ref
        call(base, token, "POST", f"/libraries/{lib_id}/scan")
        print(f"external library {path}: {action}, scan queued")
    return 0


def self_test():
    libs = [{"id": "L1", "ownerId": "U1", "importPaths": ["/external/photos"]}]
    users = {"a@x": "U1", "b@x": "U2"}
    wanted = [("a@x", "/external/photos/admin"), ("b@x", "/external/photos/user1")]
    assert plan(libs, users, wanted) == [("move", "L1", "/external/photos/admin"),
                                         ("create", "U2", "/external/photos/user1")], plan(libs, users, wanted)
    done = [{"id": "L1", "importPaths": ["/external/photos/admin"]}, {"id": "L2", "importPaths": ["/external/photos/user1"]}]
    assert plan(done, users, wanted) == [("keep", "L1", "/external/photos/admin"), ("keep", "L2", "/external/photos/user1")]
    assert plan([], users, wanted)[0] == ("create", "U1", "/external/photos/admin")
    assert plan([], {"a@x": "U1"}, wanted)[1] == ("missing-user", "b@x", "/external/photos/user1")
    # The legacy root goes only to the first pair; a second user never inherits it.
    assert plan(libs, users, wanted[1:]) == [("create", "U2", "/external/photos/user1")]
    print("immich_libraries self-test: ok")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except (urllib.error.URLError, KeyError, ValueError) as e:
        print(f"immich_libraries: {type(e).__name__}", file=sys.stderr)
        sys.exit(1)
