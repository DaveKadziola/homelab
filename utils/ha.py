#!/usr/bin/env python3
"""Control Home Assistant and deploy its config from this repo (DEV twin VM or the prod T620).

  utils/ha.py --env prod state [entity_id]
  utils/ha.py --env prod call light.turn_on --data '{"entity_id": "light.desk"}'
  utils/ha.py --env prod status                 core version, add-on states, deployed revision (JSON)
  utils/ha.py --env prod check                  core config check (exit 1 when not valid)
  utils/ha.py --env prod reload                 reload every YAML integration that can reload
  utils/ha.py --env dev deploy [--dry-run]      homeassistant/packages -> <config>/packages, check, reload
  utils/ha.py --env prod export-ui --dest DIR [--keep 30]
  utils/ha.py --env prod restore-ui --src DIR --version STAMP [--file automations.yaml] [--dry-run]
  utils/ha.py --env prod backup --dest DIR [--keep 2]
  utils/ha.py --env dev bootstrap [--dry-run]   onboarding (DEV only), API token, add-ons SSH + Kuma
  utils/ha.py --self-test

URL: config/storage.yml environments.<env>.ha_url (HA_URL overrides). Secrets: the environment
variable of the same name, else ~/.homelab-secrets/<env>/<NAME> (HOMELAB_SECRETS_DIR): HA_TOKEN,
HA_SSH_PRIV (Terminal & SSH add-on, root@<host>:22; its public half becomes the add-on's
authorized key), HA_BACKUP_PASSWORD, HA_ADMIN_PASSWORD (DEV onboarding only). The repo manages only <config>/packages; the YAML files the UI writes
(automations, scripts, scenes, configuration.yaml) are exported as snapshots and restored on
request, never overwritten by a deploy. Values of secrets are never printed.
Exit code: 0 ok, 1 failure or invalid config, 2 usage error or missing config/secret.
"""
import argparse
import base64
import difflib
import hashlib
import io
import json
import os
import shutil
import socket
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKAGES = ROOT / "homeassistant" / "packages"
UI_FILES = ["automations.yaml", "scripts.yaml", "scenes.yaml", "configuration.yaml"]
INCLUDE = "packages: !include_dir_named packages"
REVISION_ENTITY = "sensor.homelab_config_revision"
SSH_ADDON = "core_ssh"


class Stop(Exception):
    """A condition the operator has to look at; message is safe to print."""


# --------------------------------------------------------------------------- config and secrets

def ha_url(env):
    if os.environ.get("HA_URL"):
        return os.environ["HA_URL"].rstrip("/")
    import yaml  # noqa: PLC0415 - only needed here; the self-test runs without it
    st = yaml.safe_load(open(ROOT / "config" / "storage.yml"))["environments"][env]
    if not st.get("ha_url"):
        raise Stop(f"config/storage.yml environments.{env}.ha_url is empty")
    return st["ha_url"].rstrip("/")


def secret(env, name, required=True):
    if os.environ.get(name):
        return os.environ[name]
    base = Path(os.environ.get("HOMELAB_SECRETS_DIR", Path.home() / ".homelab-secrets"))
    for path in (base / env / name, base / name):
        if path.is_file():
            return path.read_text().strip("\r\n")
    if required:
        raise Stop(f"{name} is not in the environment or {base / env / name}")
    return None


# --------------------------------------------------------------------------- HTTP API

class Api:
    def __init__(self, url, token):
        self.url, self.token = url, token

    def call(self, method, path, body=None, timeout=60, raw=False):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(self.url + path, data=data, method=method)
        req.add_header("Authorization", f"Bearer {self.token}")
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            resp = urllib.request.urlopen(req, timeout=timeout)
        except urllib.error.HTTPError as e:
            raise Stop(f"{method} {path}: HTTP {e.code}") from None
        except (urllib.error.URLError, OSError) as e:
            raise Stop(f"{method} {path}: {type(e).__name__}") from None
        if raw:
            return resp
        text = resp.read().decode() or "null"
        return json.loads(text)

    def supervisor(self, method, path, body=None, timeout=60):
        """Supervisor API over the websocket command the UI uses; the REST proxy refuses most of it
        to a token (401 for add-on install on HAOS 18.3). Returns the Supervisor's `data`."""
        msg = {"type": "supervisor/api", "endpoint": path, "method": method.lower()}
        if body is not None:
            msg["data"] = body
        if timeout > 60:
            msg["timeout"] = None  # long jobs (install, backup): no Supervisor-side timeout
        return ws_call(self.url, self.token, msg, timeout) or {}

    def wait_up(self, seconds=600):
        end = time.time() + seconds
        while time.time() < end:
            try:
                self.call("GET", "/api/", timeout=10)
                return
            except Stop:
                time.sleep(5)
        raise Stop(f"Home Assistant did not answer within {seconds} s")


def api_for(env):
    return Api(ha_url(env), secret(env, "HA_TOKEN"))


# --------------------------------------------------------------------------- websocket (stdlib)

def ws_call(url, token, msg, timeout=30):
    """One command over the HA websocket API; small client, text frames only."""
    u = urllib.parse.urlparse(url)
    sock = socket.create_connection((u.hostname, u.port or 80), timeout=timeout)
    key = base64.b64encode(os.urandom(16)).decode()
    sock.sendall((f"GET /api/websocket HTTP/1.1\r\nHost: {u.hostname}:{u.port or 80}\r\n"
                  f"Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
                  "Sec-WebSocket-Version: 13\r\n\r\n").encode())
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = sock.recv(4096)
        if not chunk:
            raise Stop("websocket: connection closed during upgrade")
        data += chunk
    head, data = data.split(b"\r\n\r\n", 1)
    if b" 101 " not in head.split(b"\r\n")[0]:
        raise Stop("websocket: upgrade refused")
    buf = [data]

    def need(n):
        while len(buf[0]) < n:
            chunk = sock.recv(65536)
            if not chunk:
                raise Stop("websocket: connection closed")
            buf[0] += chunk

    def recv():
        need(2)
        n, off = buf[0][1] & 0x7F, 2
        if n == 126:
            need(4)
            n, off = int.from_bytes(buf[0][2:4], "big"), 4
        elif n == 127:
            need(10)
            n, off = int.from_bytes(buf[0][2:10], "big"), 10
        need(off + n)
        payload, buf[0] = buf[0][off:off + n], buf[0][off + n:]
        return json.loads(payload)

    def send(obj):
        sock.sendall(ws_frame(json.dumps(obj).encode(), os.urandom(4)))

    try:
        recv()  # auth_required
        send({"type": "auth", "access_token": token})
        if recv().get("type") != "auth_ok":
            raise Stop("websocket: authentication failed")
        send({"id": 1, **msg})
        while True:
            r = recv()
            if r.get("id") == 1 and r.get("type") == "result":
                break
    finally:
        sock.close()
    if not r.get("success"):
        err = r.get("error") or {}
        what = msg.get("endpoint") or msg.get("type")
        raise Stop(f"websocket {what}: {err.get('code')}: {str(err.get('message'))[:200]}")
    return r.get("result")


def ws_frame(payload, mask):
    n = len(payload)
    head = bytes([0x81, 0x80 | n]) if n < 126 else bytes([0x81, 0x80 | 126]) + n.to_bytes(2, "big")
    return head + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload))


# --------------------------------------------------------------------------- SSH to the add-on

class Ssh:
    def __init__(self, env):
        self.host = urllib.parse.urlparse(ha_url(env)).hostname
        self.key = secret(env, "HA_SSH_PRIV")
        self._dir = None
        self._cfg = None

    def run(self, command, data=None, check=True):
        if self._dir is None:
            self._dir = tempfile.mkdtemp(prefix="ha-ssh-")
            key = Path(self._dir) / "key"
            key.write_text(self.key.rstrip("\n") + "\n")
            key.chmod(0o600)
        cmd = ["ssh", "-i", str(Path(self._dir) / "key"), "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
               "-o", "StrictHostKeyChecking=accept-new", "-o", "LogLevel=ERROR", f"root@{self.host}", command]
        p = subprocess.run(cmd, input=data, capture_output=True, timeout=600)
        if check and p.returncode != 0:
            raise Stop(f"ssh root@{self.host}: exit {p.returncode}: {p.stderr.decode(errors='replace').strip()[:200]}")
        return p

    def config_dir(self):
        if self._cfg is None:
            out = self.run("if [ -d /homeassistant ]; then echo /homeassistant; else echo /config; fi")
            self._cfg = out.stdout.decode().strip()
        return self._cfg

    def close(self):
        if self._dir:
            shutil.rmtree(self._dir, ignore_errors=True)


# --------------------------------------------------------------------------- pure helpers

def render_packages(src, revision):
    """{file name: bytes} of the packages to deploy, with the revision filled in."""
    out = {}
    for path in sorted(Path(src).glob("*.yaml")):
        out[path.name] = path.read_bytes().replace(b"@REVISION@", revision.encode())
    return out


def tar_bytes(files):
    bio = io.BytesIO()
    with tarfile.open(fileobj=bio, mode="w") as tar:
        for name, content in sorted(files.items()):
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = len(content), 0o644, 0
            tar.addfile(info, io.BytesIO(content))
    return bio.getvalue()


def untar_bytes(data):
    out = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r") as tar:
        for m in tar.getmembers():
            if m.isfile() and "/" not in m.name.strip("./"):
                out[Path(m.name).name] = tar.extractfile(m).read()
    return out


def sha_map(files):
    return {name: hashlib.sha256(content).hexdigest() for name, content in files.items()}


def changes(current, wanted):
    """Lines 'add/change/remove <name>' between two {name: sha256} maps."""
    out = []
    for name in sorted(set(current) | set(wanted)):
        if name not in current:
            out.append(f"add    {name}")
        elif name not in wanted:
            out.append(f"remove {name}")
        elif current[name] != wanted[name]:
            out.append(f"change {name}")
    return out


def include_patch(text):
    """(new configuration.yaml text or None when already included). Raises Stop when unsure."""
    if any(line.strip() == INCLUDE for line in text.splitlines()):
        return None
    if any(line.rstrip() == "homeassistant:" for line in text.splitlines()):
        raise Stop("configuration.yaml has a `homeassistant:` block without the packages line - "
                   f"add `  {INCLUDE}` to it by hand once")
    if any(line.startswith("homeassistant:") for line in text.splitlines()):
        raise Stop("configuration.yaml has an inline `homeassistant:` value - add the packages line by hand once")
    return text.rstrip("\n") + f"\n\nhomeassistant:\n  {INCLUDE}\n"


def snapshots_to_drop(names, keep):
    stamps = sorted((n for n in names if len(n) == 16 and n.endswith("Z") and n[8] == "T"), reverse=True)
    return stamps[keep:]


def stamp():
    return time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())


# --------------------------------------------------------------------------- commands

def cmd_state(args):
    api = api_for(args.env)
    print(json.dumps(api.call("GET", "/api/states" + (f"/{args.entity}" if args.entity else "")), indent=2))
    return 0


def cmd_call(args):
    if args.service.count(".") != 1:
        raise Stop("service must be <domain>.<service>")
    domain, service = args.service.split(".")
    body = json.loads(args.data) if args.data else {}
    print(json.dumps(api_for(args.env).call("POST", f"/api/services/{domain}/{service}", body), indent=2))
    return 0


def check(api):
    r = api.call("POST", "/api/config/core/check_config", {}, timeout=300)
    if r.get("result") != "valid":
        print(f"config check: {r.get('result')}: {r.get('errors')}", file=sys.stderr)
        return False
    print("config check: valid")
    return True


def cmd_status(args):
    """Core version, add-on states and the deployed revision, as JSON (read-only)."""
    api = api_for(args.env)
    core = api.supervisor("GET", "/core/info")
    addons = {a["slug"]: a.get("state") for a in api.supervisor("GET", "/addons").get("addons", [])}
    try:
        revision = api.call("GET", f"/api/states/{REVISION_ENTITY}").get("state")
    except Stop:
        revision = None
    print(json.dumps({"core": core.get("version"), "addons": addons, "revision": revision}))
    return 0


def cmd_check(args):
    return 0 if check(api_for(args.env)) else 1


def cmd_reload(args):
    api_for(args.env).call("POST", "/api/services/homeassistant/reload_all", {}, timeout=300)
    print("reloaded")
    return 0


def remote_files(ssh, directory):
    # Busybox tar on the add-on: an --exclude pattern also matches the "." root, so name the files.
    p = ssh.run(f"cd {directory} 2>/dev/null && ls *.yaml >/dev/null 2>&1 && tar -cf - *.yaml || true")
    return untar_bytes(p.stdout) if p.stdout else {}


def cmd_deploy(args):
    revision = os.environ.get("GITHUB_SHA") or subprocess.run(
        ["git", "-C", str(ROOT), "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
    wanted = render_packages(args.src or PACKAGES, revision)
    if not wanted:
        raise Stop("no packages to deploy")
    api, ssh = api_for(args.env), Ssh(args.env)
    try:
        cfg = ssh.config_dir()
        diff = changes(sha_map(remote_files(ssh, f"{cfg}/packages")), sha_map(wanted))
        conf = ssh.run(f"cat {cfg}/configuration.yaml").stdout.decode()
        patched = include_patch(conf)
        for line in diff or ["packages: no change"]:
            print(line)
        if patched:
            print("configuration.yaml: add the packages include (needs a restart)")
        if args.dry_run:
            print("dry run - nothing changed")
            return 0
        if diff:
            ssh.run(f"set -e; cd {cfg}; rm -rf .packages.new .packages.old; mkdir .packages.new; "
                    f"tar -xf - -C .packages.new; if [ -d packages ]; then mv packages .packages.old; fi; "
                    f"mv .packages.new packages", data=tar_bytes(wanted))
        if patched:
            ssh.run(f"set -e; cd {cfg}; cp configuration.yaml .configuration.yaml.homelab-{stamp()}; "
                    f"cat > configuration.yaml", data=patched.encode())
        if not check(api):
            rollback = f"cd {cfg}; if [ -d .packages.old ]; then rm -rf packages; mv .packages.old packages; fi"
            if patched:
                rollback += "; printf '%s' \"$(cat)\" > configuration.yaml"
            ssh.run(rollback, data=conf.encode() if patched else None, check=False)
            raise Stop("config check failed - previous packages restored")
        ssh.run(f"rm -rf {cfg}/.packages.old", check=False)
        if patched:
            try:
                api.call("POST", "/api/services/homeassistant/restart", {}, timeout=60)
            except Stop:
                pass  # core drops the connection while it restarts
            time.sleep(20)
            api.wait_up()
        elif diff:
            api.call("POST", "/api/services/homeassistant/reload_all", {}, timeout=300)
        end = time.time() + 120
        while True:
            try:
                state = api.call("GET", f"/api/states/{REVISION_ENTITY}").get("state")
            except Stop:
                state = None
            if state == revision:
                print(f"{REVISION_ENTITY} = {revision}")
                return 0
            if time.time() > end:
                raise Stop(f"{REVISION_ENTITY} is {state!r}, expected {revision}")
            time.sleep(5)
    finally:
        ssh.close()


def cmd_export_ui(args):
    ssh = Ssh(args.env)
    try:
        cfg = ssh.config_dir()
        names = " ".join(UI_FILES)
        p = ssh.run(f"cd {cfg} && tar -cf - $(for f in {names}; do [ -f $f ] && echo $f; done)")
        files = untar_bytes(p.stdout)
    finally:
        ssh.close()
    dest = Path(args.dest)
    dest.mkdir(parents=True, exist_ok=True)
    existing = sorted(d.name for d in dest.iterdir() if d.is_dir())
    latest = [n for n in existing if n not in snapshots_to_drop(existing, 1)]
    if latest:
        old = {f.name: f.read_bytes() for f in (dest / latest[0]).iterdir() if f.is_file()}
        if sha_map(old) == sha_map(files):
            print(f"no change since {latest[0]}")
            return 0
    new = dest / stamp()
    new.mkdir()
    for name, content in files.items():
        (new / name).write_bytes(content)
    print(f"snapshot {new.name}: {', '.join(sorted(files))}")
    for name in snapshots_to_drop([d.name for d in dest.iterdir() if d.is_dir()], args.keep):
        shutil.rmtree(dest / name)
        print(f"pruned {name}")
    return 0


def cmd_restore_ui(args):
    src = Path(args.src) / args.version
    if not src.is_dir():
        raise Stop(f"no snapshot {src}")
    names = [args.file] if args.file else sorted(f.name for f in src.iterdir() if f.name in UI_FILES)
    wanted = {n: (src / n).read_bytes() for n in names}
    api, ssh = api_for(args.env), Ssh(args.env)
    try:
        cfg = ssh.config_dir()
        current = {n: ssh.run(f"cat {cfg}/{n}", check=False).stdout for n in names}
        for n in names:
            d = list(difflib.unified_diff(current[n].decode(errors="replace").splitlines(),
                                          wanted[n].decode(errors="replace").splitlines(),
                                          f"ha:{n}", f"{args.version}/{n}", lineterm=""))
            print("\n".join(d) if d else f"{n}: same as {args.version}")
        if args.dry_run:
            print("dry run - nothing changed")
            return 0
        keep = f".restore-{stamp()}"
        ssh.run(f"set -e; cd {cfg}; mkdir {keep}; for f in {' '.join(names)}; do [ -f $f ] && cp $f {keep}/; done; "
                "tar -xf - -C .", data=tar_bytes(wanted))
        if not check(api):
            ssh.run(f"cd {cfg} && cp {keep}/* . ", check=False)
            raise Stop(f"config check failed - previous files restored from {cfg}/{keep}")
        api.call("POST", "/api/services/homeassistant/reload_all", {}, timeout=300)
        print(f"restored {', '.join(names)} from {args.version}; previous copies in {cfg}/{keep}")
        return 0
    finally:
        ssh.close()


def cmd_backup(args):
    api = api_for(args.env)
    password = secret(args.env, "HA_BACKUP_PASSWORD")
    dest = Path(args.dest)
    dest.mkdir(parents=True, exist_ok=True)
    name = f"homelab-{stamp()}"
    slug = api.supervisor("POST", "/backups/new/full", {"name": name, "password": password}, timeout=3600)["slug"]
    part = dest / f"ha-full-{name[8:]}.tar.part"
    try:
        with api.call("GET", f"/api/hassio/backups/{slug}/download", timeout=3600, raw=True) as resp, open(part, "wb") as f:
            shutil.copyfileobj(resp, f, 1 << 20)
        if part.stat().st_size == 0:
            raise Stop("downloaded backup is empty")
        part.rename(part.with_suffix(""))
    finally:
        part.unlink(missing_ok=True)
        # The copy on the NAS is the point; do not let pulled backups fill the HA disk.
        api.supervisor("DELETE", f"/backups/{slug}")
    files = sorted(dest.glob("ha-full-*.tar"), key=lambda p: p.name, reverse=True)
    for old in files[args.keep:]:
        old.unlink()
    print(f"backup {files[0].name} ({files[0].stat().st_size // (1 << 20)} MiB), kept {min(len(files), args.keep)}")
    return 0


def ensure_addon(api, slug, options, dry_run, network=None):
    info = None
    try:
        info = api.supervisor("GET", f"/addons/{slug}/info")
    except Stop:
        pass
    if not info or not info.get("version"):
        print(f"{slug}: install")
        if dry_run:
            return
        api.supervisor("POST", f"/store/addons/{slug}/install", timeout=1800)
        info = api.supervisor("GET", f"/addons/{slug}/info")
    changed = False
    if options is not None:
        merged = {**info.get("options", {}), **options}
        if merged != info.get("options"):
            print(f"{slug}: set options {sorted(options)}")
            changed = True
            if not dry_run:
                api.supervisor("POST", f"/addons/{slug}/options", {"options": merged})
    if network and any(info.get("network", {}).get(k) != v for k, v in network.items()):
        print(f"{slug}: publish ports {network}")
        changed = True
        if not dry_run:
            api.supervisor("POST", f"/addons/{slug}/options", {"network": {**info.get("network", {}), **network}})
    if info.get("boot") != "auto":
        print(f"{slug}: start at boot")
        if not dry_run:
            api.supervisor("POST", f"/addons/{slug}/options", {"boot": "auto"})
    if info.get("state") != "started":
        print(f"{slug}: start")
        if not dry_run:
            api.supervisor("POST", f"/addons/{slug}/start", timeout=600)
    elif changed:
        print(f"{slug}: restart (new options)")
        if not dry_run:
            api.supervisor("POST", f"/addons/{slug}/restart", timeout=600)
    if not changed and info.get("state") == "started" and info.get("boot") == "auto":
        print(f"{slug}: ok")


def onboard(env, url):
    """DEV only: owner account + onboarding steps; returns a short-lived access token."""
    password = secret(env, "HA_ADMIN_PASSWORD")
    client = url + "/"

    def post(path, body, token=None, form=False):
        data = urllib.parse.urlencode(body).encode() if form else json.dumps(body).encode()
        req = urllib.request.Request(url + path, data=data, method="POST")
        req.add_header("Content-Type", "application/x-www-form-urlencoded" if form else "application/json")
        if token:
            req.add_header("Authorization", f"Bearer {token}")
        try:
            return json.loads(urllib.request.urlopen(req, timeout=60).read().decode() or "null")
        except urllib.error.HTTPError as e:
            raise Stop(f"POST {path}: HTTP {e.code}") from None

    done = {s["step"]: s["done"] for s in json.loads(urllib.request.urlopen(url + "/api/onboarding", timeout=30).read())}
    if not done.get("user"):
        code = post("/api/onboarding/users", {"client_id": client, "name": "Homelab Admin", "username": "admin",
                                              "password": password, "language": "en"})["auth_code"]
    else:
        flow = post("/auth/login_flow", {"client_id": client, "handler": ["homeassistant", None], "redirect_uri": client})
        r = post(f"/auth/login_flow/{flow['flow_id']}", {"client_id": client, "username": "admin", "password": password})
        if r.get("type") != "create_entry":
            raise Stop("login with HA_ADMIN_PASSWORD failed")
        code = r["result"]
    token = post("/auth/token", {"grant_type": "authorization_code", "code": code, "client_id": client}, form=True)["access_token"]
    for step, body in (("core_config", {}), ("analytics", {}), ("integration", {"client_id": client, "redirect_uri": client})):
        if not done.get(step):
            post(f"/api/onboarding/{step}", body, token)
    return token


def cmd_bootstrap(args):
    url = ha_url(args.env)
    token = secret(args.env, "HA_TOKEN", required=False)
    if not token:
        if args.env != "dev":
            raise Stop("HA_TOKEN missing: create a long-lived token in the HA profile (owner step)")
        if args.dry_run:
            print("would: onboarding/login and create HA_TOKEN")
            return 0
        access = onboard(args.env, url)
        token = ws_call(url, access, {"type": "auth/long_lived_access_token", "client_name": "homelab", "lifespan": 3650})
        base = Path(os.environ.get("HOMELAB_SECRETS_DIR", Path.home() / ".homelab-secrets")) / args.env
        base.mkdir(parents=True, exist_ok=True)
        path = base / "HA_TOKEN"
        path.write_text(token + "\n")
        path.chmod(0o600)
        print(f"HA_TOKEN written to {path}")
    api = Api(url, token)
    with tempfile.TemporaryDirectory() as d:
        key = Path(d) / "key"
        key.write_text(secret(args.env, "HA_SSH_PRIV").rstrip("\n") + "\n")
        key.chmod(0o600)
        pub = subprocess.run(["ssh-keygen", "-y", "-f", str(key)], capture_output=True, text=True, check=True).stdout
    ensure_addon(api, SSH_ADDON, {"authorized_keys": [pub.strip()], "password": "",
                                  "server": {"tcp_forwarding": False}}, args.dry_run, network={"22/tcp": 22})
    kuma = [a["slug"] for a in api.supervisor("GET", "/store/addons").get("addons", [])
            if a.get("name") == "Uptime Kuma"]
    if not kuma:
        raise Stop("Uptime Kuma is not in the add-on store (Home Assistant Community Add-ons repository)")
    ensure_addon(api, kuma[0], None, args.dry_run)
    print("bootstrap done" if not args.dry_run else "dry run - nothing changed")
    return 0


# --------------------------------------------------------------------------- self-test

def self_test():
    with tempfile.TemporaryDirectory() as d:
        Path(d, "a.yaml").write_text("state: '@REVISION@'\n")
        Path(d, "b.txt").write_text("ignored")
        files = render_packages(d, "abc123")
        assert files == {"a.yaml": b"state: 'abc123'\n"}, files
        assert untar_bytes(tar_bytes(files)) == files

        dest = Path(d) / "snaps"
        for name in ("20261001T000000Z", "20261003T000000Z", "20261002T000000Z", "notes"):
            (dest / name).mkdir(parents=True)
        assert snapshots_to_drop([p.name for p in dest.iterdir()], 2) == ["20261001T000000Z"]
        assert snapshots_to_drop(["x"], 0) == []

    cur, want = {"a": "1", "b": "2", "c": "3"}, {"a": "1", "b": "9", "d": "4"}
    assert changes(cur, want) == ["change b", "remove c", "add    d"], changes(cur, want)
    assert changes(want, want) == []

    assert include_patch(f"default_config:\nhomeassistant:\n  {INCLUDE}\n") is None
    assert include_patch("default_config:\n") == f"default_config:\n\nhomeassistant:\n  {INCLUDE}\n"
    for text in ("homeassistant:\n  name: x\n", "homeassistant: !include ha.yaml\n"):
        try:
            include_patch(text)
        except Stop:
            continue
        raise AssertionError(text)

    frame = ws_frame(b"hi", b"\x01\x02\x03\x04")
    assert frame[:2] == b"\x81\x82" and frame[2:6] == b"\x01\x02\x03\x04"
    assert bytes(b ^ frame[2:6][i % 4] for i, b in enumerate(frame[6:])) == b"hi"
    big = ws_frame(b"x" * 300, b"\0\0\0\0")
    assert big[1] == 0x80 | 126 and int.from_bytes(big[2:4], "big") == 300

    os.environ.pop("HA_TEST_SECRET", None)
    with tempfile.TemporaryDirectory() as d:
        os.environ["HOMELAB_SECRETS_DIR"] = d
        Path(d, "dev").mkdir()
        Path(d, "dev", "HA_TEST_SECRET").write_text("s3cret\n")
        assert secret("dev", "HA_TEST_SECRET") == "s3cret"
        assert secret("prod", "HA_TEST_SECRET", required=False) is None
        os.environ["HA_TEST_SECRET"] = "fromenv"
        assert secret("prod", "HA_TEST_SECRET") == "fromenv"
        del os.environ["HA_TEST_SECRET"], os.environ["HOMELAB_SECRETS_DIR"]
    print("self-test ok")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--env", choices=["dev", "prod"])
    parser.add_argument("--self-test", action="store_true", help="test the helpers, no Home Assistant")
    sub = parser.add_subparsers(dest="cmd")
    p = sub.add_parser("state")
    p.add_argument("entity", nargs="?")
    p = sub.add_parser("call")
    p.add_argument("service")
    p.add_argument("--data")
    sub.add_parser("status")
    sub.add_parser("check")
    sub.add_parser("reload")
    p = sub.add_parser("deploy")
    p.add_argument("--src", help="packages directory (default homeassistant/packages)")
    p.add_argument("--dry-run", action="store_true")
    p = sub.add_parser("export-ui")
    p.add_argument("--dest", required=True)
    p.add_argument("--keep", type=int, default=30)
    p = sub.add_parser("restore-ui")
    p.add_argument("--src", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--file", choices=UI_FILES)
    p.add_argument("--dry-run", action="store_true")
    p = sub.add_parser("backup")
    p.add_argument("--dest", required=True)
    p.add_argument("--keep", type=int, default=2)
    p = sub.add_parser("bootstrap")
    p.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    if not args.env or not args.cmd:
        parser.error("--env and a command are required")
    try:
        return globals()["cmd_" + args.cmd.replace("-", "_")](args)
    except Stop as e:
        print(f"STOP: {e}", file=sys.stderr)
        return 2 if "missing" in str(e) or "not in the environment" in str(e) or "is empty" in str(e) else 1


if __name__ == "__main__":
    sys.exit(main())
