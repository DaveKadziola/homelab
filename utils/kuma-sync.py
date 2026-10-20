#!/usr/bin/env python3
"""Make an Uptime Kuma instance match config/monitoring.yml and config/services.yml.

  ~/.local/share/homelab/kuma-venv/bin/python utils/kuma-sync.py --env dev [--dry-run]
  utils/kuma-sync.py --setup-venv      create that venv, install utils/requirements-kuma.txt
  utils/kuma-sync.py --self-test

Kuma: config/monitoring.yml environments.<env>.kuma_url. Desired state, every name prefixed
`homelab:` - monitors without the prefix are never read for changes, edited or deleted:
  - one monitor per service in config/services.yml with check http/https (2xx-3xx, https ignores
    TLS) or tcp, when its compose profile is enabled for the env (COMPOSE_PROFILES, else the
    profiles of config/services.yml environments.<env>); `optional: true`
    services are left out, as the smoke suite never fails them
  - extra_monitors.<env> (http, port, ping); all of these every 60 s with 1 retry
  - a push monitor `homelab:backup-<stream>` per backups[] stream of the env, heartbeat interval
    max_age_hours, push token = first 24 hex of sha256("<KUMA_PUSH_SECRET>:<stream>")
  - SMTP notification `homelab: mail` to environment_email.<env> (config/identities.yml), the
    default for new monitors and attached to every homelab: monitor
A homelab: monitor that is not desired any more is deleted. Only the fields this tool sets are
compared and written. A fresh Kuma gets its SQLite database and the `admin` account.

Secrets: the environment variable of the same name, else ~/.homelab-secrets/<env>/<NAME>
(HOMELAB_SECRETS_DIR): KUMA_ADMIN_PASSWORD, KUMA_PUSH_SECRET (on DEV generated into the cache
when missing), SMTP_USERNAME + SMTP_PASSWORD (only when smtp.security is not none; the user is
also the sender). Values of secrets are never printed. Output: one line per object,
`create|update|delete|ok <name>`.
Exit code: 0 ok, 1 failure, 2 usage error or missing secret.
"""
import argparse
import contextlib
import hashlib
import io
import json
import os
import secrets
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VENV = Path.home() / ".local" / "share" / "homelab" / "kuma-venv"
PREFIX = "homelab:"
MAIL = "homelab: mail"
ADMIN = "admin"
CHECK = {"interval": 60, "retryInterval": 60, "maxretries": 1}
HTTP_OK = ["200-299", "300-399"]


class Stop(Exception):
    """A condition the operator has to look at; message is safe to print."""


class Usage(Stop):
    """Exit 2: usage error or missing secret."""


# --------------------------------------------------------------------------- config and secrets

def load(name):
    import yaml  # noqa: PLC0415 - only needed here; the self-test runs without it
    return yaml.safe_load(open(ROOT / "config" / name))


def secrets_dir():
    return Path(os.environ.get("HOMELAB_SECRETS_DIR", Path.home() / ".homelab-secrets"))


def secret(env, name, required=True):
    if os.environ.get(name):
        return os.environ[name]
    base = secrets_dir()
    for path in (base / env / name, base / name):
        if path.is_file():
            return path.read_text().strip("\r\n")
    if required:
        raise Usage(f"{name} is not in the environment or {base / env / name}")
    return None


def secret_or_generate(env, name, dry_run):
    """DEV only: a missing secret is generated into the cache (a dry run keeps it in memory)."""
    value = secret(env, name, required=env != "dev")
    if value:
        return value
    value = secrets.token_urlsafe(24)  # 32 characters
    path = secrets_dir() / env / name
    if dry_run:
        print(f"would generate {name} into {path}")
        return value
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(value + "\n")
    print(f"generated {name} into {path}")
    return value


# --------------------------------------------------------------------------- desired state (pure)

def enabled_profiles(env, environ, services):
    """COMPOSE_PROFILES, else config/services.yml environments.<env>.profiles - the deploy's default."""
    if environ.get("COMPOSE_PROFILES"):
        return set(environ["COMPOSE_PROFILES"].split(","))
    profiles = (services.get("environments", {}).get(env) or {}).get("profiles")
    if not profiles:
        raise Stop(f"config/services.yml environments.{env}.profiles is empty")
    return set(profiles.split(","))


def push_token(push_secret, stream):
    return hashlib.sha256(f"{push_secret}:{stream}".encode()).hexdigest()[:24]


def desired_monitors(env, services, monitoring, profiles, push_secret, notification_id):
    """{name: fields}; the fields are the only ones the tool writes and compares."""
    host = services["environments"][env]["host"]
    out = {}

    def put(name, fields):
        if PREFIX + name in out:
            raise Stop(f"monitor name {name} is declared twice")
        out[PREFIX + name] = {**fields, "notificationIDList": [notification_id] if notification_id else []}

    def http(url, ignore_tls):
        return {"type": "http", "url": url, "ignoreTls": ignore_tls, "accepted_statuscodes": HTTP_OK, **CHECK}

    for s in services["services"]:
        if s.get("optional") or (s.get("profile") and s["profile"] not in profiles):
            continue
        if s["check"] in ("http", "https"):
            put(s["name"], http(f"{s['check']}://{host}:{s['port']}{s.get('path') or '/'}", s["check"] == "https"))
        elif s["check"] == "tcp":
            put(s["name"], {"type": "port", "hostname": host, "port": s["port"], **CHECK})
        elif s["check"] != "container":
            raise Stop(f"service {s['name']}: unknown check {s['check']!r} in config/services.yml")
    for m in (monitoring.get("extra_monitors") or {}).get(env) or []:
        if m["type"] == "http":
            put(m["name"], http(m["url"], bool(m.get("ignore_tls"))))
        elif m["type"] == "port":
            put(m["name"], {"type": "port", "hostname": m["host"], "port": m["port"], **CHECK})
        elif m["type"] == "ping":
            put(m["name"], {"type": "ping", "hostname": m["host"], **CHECK})
        else:
            raise Stop(f"extra_monitors.{env} {m['name']}: unknown type {m['type']!r}")
    for b in monitoring.get("backups") or []:
        if env in b["envs"]:
            # No retry: max_age_hours already holds the slack; once down, re-check hourly.
            put(f"backup-{b['stream']}", {"type": "push", "pushToken": push_token(push_secret, b["stream"]),
                                          "interval": b["max_age_hours"] * 3600, "retryInterval": 3600,
                                          "maxretries": 0})
    return out


def smtp_notification(env, monitoring, identities, username, password):
    smtp = monitoring["environments"][env]["smtp"]
    if smtp["security"] not in ("none", "starttls"):
        raise Stop(f"monitoring.yml environments.{env}.smtp.security {smtp['security']!r}: expected none or starttls")
    to = identities["environment_email"][env]
    return {"name": MAIL, "type": "smtp", "isDefault": True, "smtpHost": smtp["host"], "smtpPort": smtp["port"],
            "smtpSecure": False, "smtpIgnoreSTARTTLS": smtp["security"] == "none",
            "smtpUsername": username or "", "smtpPassword": password or "", "smtpFrom": username or to,
            "smtpTo": to}


def same(current, wanted):
    if isinstance(wanted, list):
        return sorted(current or []) == sorted(wanted)
    return current == wanted


def changed_fields(current, wanted):
    return [k for k, v in wanted.items() if not same(current.get(k), v)]


def plan(desired, existing):
    """[(action, name, changed fields)] for desired {name: fields} against existing {name: monitor}."""
    out = []
    for name in sorted(set(desired) | set(existing)):
        if name not in existing:
            out.append(("create", name, []))
        elif name not in desired:
            out.append(("delete", name, []))
        else:
            changed = changed_fields(existing[name], desired[name])
            out.append(("update" if changed else "ok", name, changed))
    return out


def line(action, name, fields):
    return f"{action} {name}" + (f" ({', '.join(fields)})" if fields else "")


# --------------------------------------------------------------------------- Kuma

def http_json(method, url, body=None, timeout=15):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def ensure_database(url, dry_run):
    """Kuma 2.x starts on a database choice page; pick the embedded SQLite. False: dry run, no database yet."""
    try:
        info = http_json("GET", url + "/setup-database-info")
    except (urllib.error.HTTPError, ValueError):
        return True  # Kuma 1.x has no database step
    except (urllib.error.URLError, OSError) as e:
        raise Stop(f"{url}: {type(e).__name__}: {e}") from None
    if not info.get("needSetup"):
        return True
    print("setup database sqlite")
    if dry_run:
        return False
    http_json("POST", url + "/setup-database", {"dbConfig": {"type": "sqlite"}})
    end = time.time() + 300
    while time.time() < end:
        time.sleep(5)
        try:
            if not http_json("GET", url + "/setup-database-info").get("needSetup"):
                return True
        except (urllib.error.URLError, OSError, ValueError):
            pass  # restarting into the main server
    raise Stop("Kuma did not come back within 300 s after the database setup")


def add_monitor(api, name, fields):
    # Raw `add`: 1.2.1 add_monitor takes no pushToken and no `conditions`, which Kuma 2.x needs (NOT NULL).
    data = api._build_monitor_data(name=name, **{k: v for k, v in fields.items() if k != "pushToken"})
    data.update(conditions=[], notificationIDList={i: True for i in fields["notificationIDList"]})
    if "pushToken" in fields:
        data["pushToken"] = fields["pushToken"]
    api._call("add", data)


def redact(text, values):
    for v in values:
        if v:
            text = text.replace(v, "<redacted>")
    return text


def connect(url):
    from uptime_kuma_api import UptimeKumaApi  # noqa: PLC0415 - the self-test runs without it

    class Api(UptimeKumaApi):
        # Kuma registers its socket handlers only after it sent the first `info`; an event that
        # arrives earlier is dropped and its call times out (seen on the first connection after
        # the database setup).
        info_seen = False

        def _event_info(self, data):
            self.info_seen = True
            super()._event_info(data)

    api = Api(url, timeout=30)
    end = time.time() + 30
    while not api.info_seen:
        if time.time() > end:
            api.disconnect()
            raise Stop("Kuma sent no info event within 30 s of connecting")
        time.sleep(0.1)
    return api


def sync(env, dry_run):
    try:
        import uptime_kuma_api  # noqa: F401, PLC0415
    except ImportError:
        raise Usage(f"uptime_kuma_api is not installed: run utils/kuma-sync.py --setup-venv, then {VENV}/bin/python "
                    "utils/kuma-sync.py") from None
    monitoring, services, identities = load("monitoring.yml"), load("services.yml"), load("identities.yml")
    url = monitoring["environments"][env]["kuma_url"].rstrip("/")
    smtp = monitoring["environments"][env]["smtp"]
    user = password = None
    if smtp["security"] != "none":
        user, password = secret(env, "SMTP_USERNAME", False), secret(env, "SMTP_PASSWORD", False)
    admin_password = secret_or_generate(env, "KUMA_ADMIN_PASSWORD", dry_run)
    push_secret = secret_or_generate(env, "KUMA_PUSH_SECRET", dry_run)
    # Monitors are worth having before the relay exists; the mail notification waits for its login.
    mail = None
    if smtp["security"] == "none" or (user and password):
        mail = smtp_notification(env, monitoring, identities, user, password)
    else:
        print(f"warn {MAIL}: SMTP_USERNAME/SMTP_PASSWORD missing - monitors without mail", file=sys.stderr)
    profiles = enabled_profiles(env, os.environ, services)

    monitors, notifications, desired = [], [], {}
    api = None
    try:
        if ensure_database(url, dry_run):
            api = connect(url)
            fresh = api.need_setup()
            if fresh:
                print(f"setup admin {ADMIN}")
                if not dry_run:
                    api.setup(ADMIN, admin_password)
            if not (dry_run and fresh):
                api.login(ADMIN, admin_password)
                monitors, notifications = api.get_monitors(), api.get_notifications()

        current = next((n for n in notifications if n.get("name") == MAIL), None)
        notification_id = current["id"] if current else None
        changed = changed_fields(current, mail) if current and mail else []
        if mail:
            print(line("create" if not current else "update" if changed else "ok", MAIL, changed))
        if mail and not dry_run and (not current or changed):
            # Raw call: 1.2.1 rejects SMTP options newer than Kuma 1.23 (smtpIgnoreSTARTTLS).
            keep = {k: v for k, v in (current or {}).items() if k not in ("id", "user_id", "is_default")}
            r = api._call("addNotification", ({**keep, **mail, "applyExisting": False}, notification_id))
            notification_id = r["id"]

        desired = desired_monitors(env, services, monitoring, profiles, push_secret,
                                   notification_id or (-1 if mail and dry_run else None))
        existing = {m["name"]: m for m in monitors if str(m.get("name", "")).startswith(PREFIX)}
        for action, name, fields in plan(desired, existing):
            print(line(action, name, fields))
            if dry_run or action == "ok":
                continue
            if action == "create":
                add_monitor(api, name, desired[name])
            elif action == "update":
                api.edit_monitor(existing[name]["id"], **{k: desired[name][k] for k in fields})
            else:
                api.delete_monitor(existing[name]["id"])
    except Exception as e:
        if isinstance(e, Stop) or type(e).__module__.split(".")[0] not in ("uptime_kuma_api", "socketio"):
            raise
        # Kuma errors can quote the SQL with the values (push token, SMTP password).
        hidden = [admin_password, push_secret, user, password] + [d.get("pushToken") for d in desired.values()]
        raise Stop(f"Kuma: {type(e).__name__}: {redact(str(e), hidden)}") from None
    finally:
        if api:
            api.disconnect()
    if dry_run:
        print("dry run - nothing changed")
    return 0


def setup_venv():
    subprocess.run([sys.executable, "-m", "venv", "--system-site-packages", str(VENV)], check=True)
    subprocess.run([str(VENV / "bin" / "pip"), "install", "--quiet", "-r",
                    str(ROOT / "utils" / "requirements-kuma.txt")], check=True)
    print(f"venv ready: {VENV}/bin/python utils/kuma-sync.py --env <env>")
    return 0


# --------------------------------------------------------------------------- self-test

def self_test():
    services = {
        "environments": {"dev": {"host": "10.0.0.5"}, "prod": {"host": "10.0.1.5"}},
        "services": [
            {"name": "web", "check": "http", "port": 80, "path": "/x"},
            {"name": "db", "check": "tcp", "port": 5432},
            {"name": "sso", "check": "https", "port": 9091, "profile": "auth"},
            {"name": "photos", "check": "http", "port": 2283, "profile": "media"},
            {"name": "agent", "check": "container", "port": 45876, "profile": "beszel-agent", "optional": True},
            {"name": "maybe", "check": "http", "port": 81, "optional": True},
            {"name": "diun", "check": "container"},
        ],
    }
    monitoring = {
        "environments": {"dev": {"smtp": {"host": "10.0.0.5", "port": 1025, "security": "none"}},
                         "prod": {"smtp": {"host": "smtp.example.org", "port": 587, "security": "starttls"}}},
        "backups": [{"stream": "postgres", "max_age_hours": 26, "envs": ["dev", "prod"]},
                    {"stream": "vzdump", "max_age_hours": 30, "envs": ["prod"]}],
        "extra_monitors": {"prod": [{"name": "pve", "type": "http", "url": "https://10.0.1.2:8006", "ignore_tls": True},
                                    {"name": "router", "type": "ping", "host": "10.0.1.1"}]},
    }
    identities = {"environment_email": {"dev": "dev@example.org", "prod": "prod@example.org"}}

    book = {"environments": {"prod": {"profiles": "media"}, "dev": {"profiles": "auth,media"}}}
    assert enabled_profiles("prod", {}, book) == {"media"}
    assert enabled_profiles("dev", {"COMPOSE_PROFILES": ""}, book) == {"auth", "media"}
    assert enabled_profiles("prod", {"COMPOSE_PROFILES": "auth"}, {}) == {"auth"}
    try:
        enabled_profiles("dev", {}, {"environments": {"dev": {}}})
        raise AssertionError("missing profiles must stop")
    except Stop:
        pass

    # Known answer: printf '%s' 's3cret:postgres' | sha256sum | cut -c1-24
    assert push_token("s3cret", "postgres") == "8505c6f6f220ca8194e4e435"

    dev = desired_monitors("dev", services, monitoring, enabled_profiles("dev", {}, book), "s3cret", 7)
    assert sorted(dev) == ["homelab:backup-postgres", "homelab:db", "homelab:photos", "homelab:sso", "homelab:web"], sorted(dev)
    assert dev["homelab:web"] == {"type": "http", "url": "http://10.0.0.5:80/x", "ignoreTls": False,
                                  "accepted_statuscodes": HTTP_OK, "notificationIDList": [7], **CHECK}, dev["homelab:web"]
    assert dev["homelab:sso"]["url"] == "https://10.0.0.5:9091/" and dev["homelab:sso"]["ignoreTls"] is True
    assert dev["homelab:db"] == {"type": "port", "hostname": "10.0.0.5", "port": 5432, "notificationIDList": [7], **CHECK}
    assert dev["homelab:backup-postgres"] == {"type": "push", "pushToken": "8505c6f6f220ca8194e4e435", "interval": 93600,
                                              "retryInterval": 3600, "maxretries": 0, "notificationIDList": [7]}

    prod = desired_monitors("prod", services, monitoring, enabled_profiles("prod", {}, book), "s3cret", 7)
    assert sorted(prod) == ["homelab:backup-postgres", "homelab:backup-vzdump", "homelab:db", "homelab:photos",
                            "homelab:pve", "homelab:router", "homelab:web"], sorted(prod)
    assert prod["homelab:web"]["url"] == "http://10.0.1.5:80/x"
    assert prod["homelab:pve"]["ignoreTls"] is True and prod["homelab:router"]["type"] == "ping"
    assert prod["homelab:backup-vzdump"]["interval"] == 30 * 3600
    for bad in ({"name": "web", "type": "ping", "host": "x"}, {"name": "x", "type": "dns", "host": "x"}):
        try:
            desired_monitors("dev", services, {**monitoring, "extra_monitors": {"dev": [bad]}}, {"media"}, "s", 1)
        except Stop:
            continue
        raise AssertionError(bad)

    mail = smtp_notification("dev", monitoring, identities, None, None)
    assert mail["smtpFrom"] == mail["smtpTo"] == "dev@example.org" and mail["smtpIgnoreSTARTTLS"] is True
    assert mail["smtpUsername"] == mail["smtpPassword"] == ""
    mail = smtp_notification("prod", monitoring, identities, "relay@example.org", "pw")
    assert mail["smtpFrom"] == "relay@example.org" and mail["smtpTo"] == "prod@example.org"
    assert mail["smtpIgnoreSTARTTLS"] is False and mail["smtpSecure"] is False and mail["smtpPort"] == 587

    want = {"homelab:a": {"type": "http", "interval": 60, "notificationIDList": [1, 2]},
            "homelab:b": {"type": "port", "port": 22}, "homelab:new": {"type": "ping"}}
    have = {"homelab:a": {"id": 1, "type": "http", "interval": 60, "notificationIDList": [2, 1], "weight": 9},
            "homelab:b": {"id": 2, "type": "port", "port": 2222}, "homelab:old": {"id": 3, "type": "ping"}}
    assert plan(want, have) == [("ok", "homelab:a", []), ("update", "homelab:b", ["port"]),
                                ("create", "homelab:new", []), ("delete", "homelab:old", [])], plan(want, have)
    assert plan(want, {}) == [("create", n, []) for n in sorted(want)]
    assert line("update", "homelab:b", ["port", "url"]) == "update homelab:b (port, url)"
    assert redact("values ('abc', 'pw1') - x", ["pw1", None, "abc"]) == "values ('<redacted>', '<redacted>') - x"

    os.environ.pop("KUMA_TEST_SECRET", None)
    with tempfile.TemporaryDirectory() as d:
        os.environ["HOMELAB_SECRETS_DIR"] = d
        try:
            secret_or_generate("prod", "KUMA_TEST_SECRET", False)
            raise AssertionError("prod must not generate")
        except Usage:
            pass
        with contextlib.redirect_stdout(io.StringIO()):
            assert len(secret_or_generate("dev", "KUMA_TEST_SECRET", True)) == 32
            assert not Path(d, "dev", "KUMA_TEST_SECRET").exists()
            value = secret_or_generate("dev", "KUMA_TEST_SECRET", False)
        assert Path(d, "dev", "KUMA_TEST_SECRET").stat().st_mode & 0o777 == 0o600
        assert secret_or_generate("dev", "KUMA_TEST_SECRET", False) == value == secret("dev", "KUMA_TEST_SECRET")
        del os.environ["HOMELAB_SECRETS_DIR"]
    print("self-test ok")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--env", choices=["dev", "prod"])
    parser.add_argument("--dry-run", action="store_true", help="print the actions, change nothing")
    parser.add_argument("--setup-venv", action="store_true", help=f"create {VENV} with the pinned requirements")
    parser.add_argument("--self-test", action="store_true", help="test the pure helpers, no Kuma")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    if args.setup_venv:
        return setup_venv()
    if not args.env:
        parser.error("--env is required")
    try:
        return sync(args.env, args.dry_run)
    except Stop as e:
        print(f"STOP: {e}", file=sys.stderr)
        return 2 if isinstance(e, Usage) else 1


if __name__ == "__main__":
    sys.exit(main())
