#!/usr/bin/env python3
"""Queue an Immich scan of the external libraries soon after the photos share changes (2026-10-24).

    photos-watch.py <photos dir> <immich api base> <key file>
    photos-watch.py --self-test

Runs on the NAS (homelab-photos-watch.service): Immich sees the folder over NFS, where it gets no
change events. inotifywait reports every change below the photos folder; once nothing has changed
for QUIET seconds, every external library is scanned (GET /libraries, POST /libraries/{id}/scan,
admin key with library.read and library.update, read from the key file at each scan, so a new key
needs no restart). A failed scan is logged and tried again at the next change; Immich's own 15-minute
scan stays the fallback. The key is never printed. Runs until stopped;
exits 1 when inotifywait ends, so systemd restarts it.
"""
import json
import os
import select
import subprocess
import sys
import time
import urllib.error
import urllib.request

QUIET = 30
EVENTS = "close_write,moved_to,moved_from,delete,create"


def wait(last_change, now, quiet=QUIET):
    """Seconds until a scan is due; None while nothing changed since the last scan."""
    return None if last_change is None else max(0.0, last_change + quiet - now)


def call(base, key, method, path):
    req = urllib.request.Request(base.rstrip("/") + path, method=method, headers={"x-api-key": key})
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read()
        return json.loads(raw) if raw else None


def scan(base, key_file):
    try:
        with open(key_file) as f:
            key = f.read().strip()
        libraries = call(base, key, "GET", "/libraries")
        for lib in libraries:
            call(base, key, "POST", f"/libraries/{lib['id']}/scan")
        print(f"change seen: scan queued for {len(libraries)} libraries", flush=True)
    except (urllib.error.URLError, OSError, ValueError, KeyError) as e:
        print(f"change seen: scan failed ({type(e).__name__} {getattr(e, 'code', '')})", flush=True)


def main(argv):
    if argv[1:] == ["--self-test"]:
        return self_test()
    photos, base, key_file = argv[1:4]
    watcher = subprocess.Popen(["inotifywait", "-m", "-r", "-q", "-e", EVENTS, photos], stdout=subprocess.PIPE)
    fd = watcher.stdout.fileno()
    print(f"watching {photos}", flush=True)
    last_change = None
    while True:
        ready, _, _ = select.select([fd], [], [], wait(last_change, time.monotonic()))
        if ready:
            # Any output is a change; the event text itself does not matter.
            if not os.read(fd, 65536):
                print(f"inotifywait ended (rc {watcher.wait()})", flush=True)
                return 1
            last_change = time.monotonic()
        else:
            scan(base, key_file)
            last_change = None


def self_test():
    assert wait(None, 5.0) is None
    assert wait(100.0, 110.0) == 20.0
    assert wait(100.0, 140.0) == 0.0
    # A later change moves the scan out again.
    assert wait(135.0, 140.0) == 25.0
    print("photos-watch self-test: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
