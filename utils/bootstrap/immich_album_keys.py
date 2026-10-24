#!/usr/bin/env python3
"""Keep one Immich API key per photos user for the album creator (decision 2026-10-23).

    printf '<email>\\t<password>\\n' ... | immich_album_keys.py <api base> <key file>
    immich_album_keys.py --self-test

The key file holds one API key per line, as salvoxia/immich-folder-album-creator reads it from
API_KEY_FILE. A key that still answers GET /users/me for a wanted user is kept. A wanted user
without one logs in with the password from stdin (empty: skipped), deletes its own keys named
NAME (their secret is lost) and gets a new key with only what the creator needs in CREATE mode:
no asset or album delete, nothing on accounts. Keys of users no longer wanted leave the file.
The file is rewritten only when it changes, readable only by the container user. Prints one line
per user and never a key or password. Exit code: 0 done, 1 self-test or API failed.
"""
import json
import os
import sys
import urllib.error
import urllib.request

NAME = "homelab-album-creator"
PERMISSIONS = ["asset.read", "album.read", "album.create", "album.update", "albumAsset.create", "user.read"]
CONTAINER_UID = 1000  # USER of the salvoxia/immich-folder-album-creator image


def plan(key_owners, wanted):
    """key_owners {key: email, None when rejected}, wanted [email] -> ({email: key} to keep, [email] to create)."""
    keep = {}
    for key, email in key_owners.items():
        if email in wanted and email not in keep:
            keep[email] = key
    return keep, [e for e in wanted if e not in keep]


def call(base, method, path, body=None, token=None, key=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if key:
        headers["x-api-key"] = key
    req = urllib.request.Request(base.rstrip("/") + path, method=method, headers=headers,
                                 data=None if body is None else json.dumps(body).encode())
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read()
        return json.loads(raw) if raw else None


def owner(base, key):
    try:
        return call(base, "GET", "/users/me", key=key)["email"]
    except urllib.error.HTTPError as e:
        # Only a rejected key is dropped; any other failure stops the run with the file unchanged.
        if e.code == 401:
            return None
        raise


def new_key(base, email, password):
    try:
        token = call(base, "POST", "/auth/login", {"email": email, "password": password})["accessToken"]
    except urllib.error.HTTPError as e:
        if e.code == 401:
            return None
        raise
    for old in call(base, "GET", "/api-keys", token=token):
        if old["name"] == NAME:
            call(base, "DELETE", f"/api-keys/{old['id']}", token=token)
    return call(base, "POST", "/api-keys", {"name": NAME, "permissions": PERMISSIONS}, token=token)["secret"]


def write(path, content):
    os.makedirs(os.path.dirname(path), mode=0o755, exist_ok=True)
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o400)
    with os.fdopen(fd, "w") as f:
        os.fchown(f.fileno(), CONTAINER_UID, CONTAINER_UID)
        f.write(content)
    os.replace(tmp, path)


def main(argv):
    if argv[1:] == ["--self-test"]:
        return self_test()
    base, path = argv[1], argv[2]
    passwords = dict(line.rstrip("\n").split("\t", 1) for line in sys.stdin if "\t" in line)
    try:
        with open(path) as f:
            current = f.read()
    except FileNotFoundError:
        current = ""
    keep, create = plan({k: owner(base, k) for k in current.split()}, list(passwords))
    for email in keep:
        print(f"album key {email}: keep")
    for email in create:
        key = new_key(base, email, passwords[email]) if passwords[email] else None
        if key is None:
            print(f"album key {email}: no login - not created")
            continue
        keep[email] = key
        print(f"album key {email}: created")
    content = "".join(keep[e] + "\n" for e in passwords if e in keep)
    if content != current:
        write(path, content)
    return 0


def self_test():
    wanted = ["a@x", "b@x"]
    assert plan({}, wanted) == ({}, ["a@x", "b@x"])
    assert plan({"K1": "a@x", "K2": None}, wanted) == ({"a@x": "K1"}, ["b@x"])
    # A key of a user no longer wanted leaves the file; a user never gets two keys in it.
    assert plan({"K1": "a@x", "K3": "a@x", "K4": "c@x"}, wanted) == ({"a@x": "K1"}, ["b@x"])
    assert plan({"K1": "a@x", "K2": "b@x"}, wanted) == ({"a@x": "K1", "b@x": "K2"}, [])
    print("immich_album_keys self-test: ok")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except (urllib.error.URLError, KeyError, ValueError, OSError) as e:
        print(f"immich_album_keys: {type(e).__name__}", file=sys.stderr)
        sys.exit(1)
