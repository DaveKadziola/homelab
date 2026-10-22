#!/usr/bin/env python3
"""Converge the Beszel hub and its local agent through the hub API (F7-B, F10-A).

utils/bootstrap/beszel.sh upserts the hub superuser and then calls this script.
It works as that superuser (superusers bypass the collection rules) and converges:

  1. the Beszel user that owns the monitored system - same login as the superuser
  2. the system <env>-apps and its agent token (fingerprints collection)
  3. <compose>/core/beszel-agent.env with KEY (hub public key) and TOKEN; beszel-agent reads it
     through env_file and dials the hub itself (WebSocket), so no deploy has to know the key
  4. one alert per threshold in config/monitoring.yml
  5. the notification address: environment_email in config/identities.yml
  6. the hub SMTP relay: config/monitoring.yml environments.<env>.smtp

    beszel_config.py --base URL --config DIR --compose-dir DIR --env ENV --system NAME
                     --host HOST --port PORT --username NAME --app-url URL
    beszel_config.py --self-test

Credentials come from the environment, never argv: BESZEL_EMAIL and BESZEL_PASSWORD, and
SMTP_USERNAME / SMTP_PASSWORD when the relay needs a login. A relay without its login is
skipped with a warning. Lines saying "converged" mean something changed.
"""

import argparse
import datetime
import json
import os
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import yaml

# Beszel alert -> (threshold, window in minutes) in config/monitoring.yml. Beszel keeps one alert
# per metric, user and system (unique index on alerts), so disk_percent_critical has no record.
# Disk has no window there; Beszel treats anything below 1 minute as 1 (the current value).
ALERTS = {
    "CPU": ("cpu_percent", "cpu_minutes"),
    "Memory": ("memory_percent", "memory_minutes"),
    "Disk": ("disk_percent", None),
}


def log(message):
    print(f"[beszel] {message}", flush=True)


def warn(message):
    print(f"[beszel] WARN {message}", file=sys.stderr, flush=True)


def q(value):
    """A PocketBase filter string literal."""
    return json.dumps(value)


class HubError(Exception):
    pass


class Hub:
    def __init__(self, base):
        self.base = base.rstrip("/")
        self.token = None

    def call(self, method, path, body=None):
        headers = {"Content-Type": "application/json"}
        if self.token:
            headers["Authorization"] = self.token
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(self.base + path, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.loads(response.read() or b"null")
        except urllib.error.HTTPError as error:
            # PocketBase error bodies name the failing field, never the submitted value.
            detail = error.read()[:300].decode(errors="replace")
            raise HubError(f"{method} {path.split('?')[0]} -> HTTP {error.code} {detail}") from None

    def first(self, collection, filter_):
        query = urllib.parse.urlencode({"perPage": 1, "filter": filter_})
        items = self.call("GET", f"/api/collections/{collection}/records?{query}")["items"]
        return items[0] if items else None

    def ensure(self, collection, record, desired, label, create_only=None):
        """Create the record, or patch the fields that differ from desired."""
        path = f"/api/collections/{collection}/records"
        if record is None:
            log(f"{label}: converged (created)")
            return self.call("POST", path, {**desired, **(create_only or {})})
        changes = {key: value for key, value in desired.items() if record.get(key) != value}
        if not changes:
            log(f"{label}: already set")
            return record
        log(f"{label}: converged ({', '.join(sorted(changes))})")
        return self.call("PATCH", f"{path}/{record['id']}", changes)


def desired_alerts(thresholds):
    return {
        name: {"value": thresholds[value], "min": thresholds[window] if window else 1}
        for name, (value, window) in ALERTS.items()
    }


def desired_smtp(relay, username, password, sender, app_url):
    """(smtp, meta) settings without the password, or None when the relay's login is missing."""
    if relay["security"] != "none" and not (username and password):
        return None
    smtp = {
        "enabled": True,
        "host": relay["host"],
        "port": relay["port"],
        # PocketBase: tls = implicit TLS; false sends STARTTLS when the server offers it.
        "tls": relay["security"] == "tls",
        "authMethod": "PLAIN" if username else "",
        "username": username,
    }
    # The relay login is the From address (Proton refuses any other).
    meta = {"senderName": "Beszel", "senderAddress": username or sender, "appURL": app_url}
    return smtp, meta


def ensure_user(hub, email, password, username):
    # Same pair as the hub's first-run form: an admin user next to the superuser.
    user = hub.ensure(
        "users",
        hub.first("users", f"email = {q(email)}"),
        {"email": email, "username": username, "role": "admin", "verified": True},
        f"user {email}",
        {"password": password, "passwordConfirm": password},
    )
    try:
        Hub(hub.base).call(
            "POST", "/api/collections/users/auth-with-password", {"identity": email, "password": password}
        )
    except HubError:
        log(f"user {email}: converged (password)")
        hub.call(
            "PATCH",
            f"/api/collections/users/records/{user['id']}",
            {"password": password, "passwordConfirm": password},
        )
    return user


def write_agent_env(core, key, token):
    """Write beszel-agent.env with the owner and mode of the compose .env; True when it changed."""
    path = os.path.join(core, "beszel-agent.env")
    content = f"KEY={key}\nTOKEN={token}\n"
    try:
        with open(path, encoding="utf-8") as current:
            if current.read() == content:
                log("agent env file: already set")
                return False
    except FileNotFoundError:
        pass
    reference = os.stat(os.path.join(core, ".env"))
    tmp = f"{path}.tmp"
    with os.fdopen(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w", encoding="utf-8") as out:
        out.write(content)
    os.chown(tmp, reference.st_uid, reference.st_gid)
    os.chmod(tmp, reference.st_mode & 0o777)
    os.replace(tmp, path)
    log(f"agent env file {path}: converged")
    return True


def start_agent(core, recreate):
    command = [
        "docker", "compose", "--project-directory", core,
        "-f", os.path.join(core, "docker-compose.yml"), "--env-file", os.path.join(core, ".env"),
        "--profile", "beszel-agent", "up", "-d", "--quiet-pull",
    ]
    if recreate:
        command.append("--force-recreate")
    subprocess.run([*command, "beszel-agent"], check=True, stdout=subprocess.DEVNULL)


def wait_up(hub, system, since, timeout=150):
    """Wait for a stats update after `since`: a stale "up" would hide an agent that just broke."""
    deadline = time.monotonic() + timeout
    while True:
        record = hub.call("GET", f"/api/collections/systems/records/{system['id']}")
        if record["status"] == "paused" or (record["status"] == "up" and record["updated"] > since):
            log(f"system {system['name']}: {record['status']}, last update {record['updated']}")
            return
        if time.monotonic() > deadline:
            raise HubError(
                f"system {system['name']} is {record['status']} without an update for {timeout}s"
                " - see the beszel-agent log"
            )
        time.sleep(5)


def ensure_remote_agents(hub, user, monitoring, env):
    """Hub records for agents that run on other hosts. Does not touch the local agent."""
    for spec in (monitoring["environments"].get(env) or {}).get("beszel_agents") or []:
        name, host, port = spec["name"], spec["host"], str(spec["port"])
        record = hub.first("systems", f"name = {q(name)}")
        owners = (record or {}).get("users", [])
        if user["id"] not in owners:
            owners = [*owners, user["id"]]
        system = hub.ensure(
            "systems", record, {"name": name, "host": host, "port": port, "users": owners},
            f"system {name}",
        )
        hub.ensure(
            "fingerprints",
            hub.first("fingerprints", f"system = {q(system['id'])}"),
            {"system": system["id"]},
            f"agent token of {name}",
            {"token": secrets.token_hex(16)},
        )
        for alert_name, values in desired_alerts(monitoring["thresholds"]).items():
            hub.ensure(
                "alerts",
                hub.first("alerts", f"user = {q(user['id'])} && system = {q(system['id'])} && name = {q(alert_name)}"),
                {"user": user["id"], "system": system["id"], "name": alert_name, **values},
                f"alert {alert_name} > {values['value']}% for {values['min']} min on {name}",
            )


def converge(args):
    with open(os.path.join(args.config, "monitoring.yml"), encoding="utf-8") as handle:
        monitoring = yaml.safe_load(handle)
    with open(os.path.join(args.config, "identities.yml"), encoding="utf-8") as handle:
        notify = yaml.safe_load(handle)["environment_email"][args.env]
    email, password = os.environ["BESZEL_EMAIL"], os.environ["BESZEL_PASSWORD"]
    core = os.path.join(args.compose_dir, "core")

    hub = Hub(args.base)
    hub.token = hub.call(
        "POST", "/api/collections/_superusers/auth-with-password", {"identity": email, "password": password}
    )["token"]

    user = ensure_user(hub, email, password, args.username)

    record = hub.first("systems", f"name = {q(args.system)}")
    owners = (record or {}).get("users", [])
    if user["id"] not in owners:
        owners = [*owners, user["id"]]
    system = hub.ensure(
        "systems", record, {"name": args.system, "host": args.host, "port": str(args.port), "users": owners},
        f"system {args.system}",
    )
    fingerprint = hub.ensure(
        "fingerprints",
        hub.first("fingerprints", f"system = {q(system['id'])}"),
        {"system": system["id"]},
        f"agent token of {args.system}",
        {"token": secrets.token_hex(16)},
    )
    key = hub.call("GET", "/api/beszel/getkey")["key"]
    # PocketBase's timestamp format, so it compares as a string; hub and agent share this host's clock.
    since = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3] + "Z"
    start_agent(core, write_agent_env(core, key, fingerprint["token"]))

    for name, values in desired_alerts(monitoring["thresholds"]).items():
        hub.ensure(
            "alerts",
            hub.first("alerts", f"user = {q(user['id'])} && system = {q(system['id'])} && name = {q(name)}"),
            {"user": user["id"], "system": system["id"], "name": name, **values},
            f"alert {name} > {values['value']}% for {values['min']} min",
        )

    record = hub.first("user_settings", f"user = {q(user['id'])}")
    settings = {**((record or {}).get("settings") or {}), "emails": [notify]}
    hub.ensure("user_settings", record, {"user": user["id"], "settings": settings}, f"alert mail to {notify}")

    relay = monitoring["environments"][args.env]["smtp"]
    smtp_user, smtp_password = os.environ.get("SMTP_USERNAME", ""), os.environ.get("SMTP_PASSWORD", "")
    wanted = desired_smtp(relay, smtp_user, smtp_password, notify, args.app_url)
    if wanted is None:
        warn(f"SMTP_USERNAME / SMTP_PASSWORD missing - hub mail via {relay['host']} not configured")
    else:
        smtp, meta = wanted
        current = hub.call("GET", "/api/settings")
        stale = [k for k, v in smtp.items() if current["smtp"].get(k) != v]
        stale += [k for k, v in meta.items() if current["meta"].get(k) != v]
        label = f"hub SMTP {relay['host']}:{relay['port']}"
        # The API never returns the stored password, so a login is re-sent on every run.
        if stale or smtp_password:
            hub.call("PATCH", "/api/settings", {"smtp": {**smtp, "password": smtp_password}, "meta": meta})
            log(f"{label}: converged ({', '.join(stale)})" if stale else f"{label}: already set, password re-sent")
        else:
            log(f"{label}: already set")

    wait_up(hub, system, since)
    ensure_remote_agents(hub, user, monitoring, args.env)


def self_test():
    thresholds = {
        "disk_percent": 80, "disk_percent_critical": 90, "memory_percent": 90,
        "memory_minutes": 10, "cpu_percent": 80, "cpu_minutes": 15,
    }
    assert desired_alerts(thresholds) == {
        "CPU": {"value": 80, "min": 15},
        "Memory": {"value": 90, "min": 10},
        "Disk": {"value": 80, "min": 1},
    }
    repo_config = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "config", "monitoring.yml")
    with open(repo_config, encoding="utf-8") as handle:
        monitoring = yaml.safe_load(handle)
    assert set(desired_alerts(monitoring["thresholds"])) == set(ALERTS)

    smtp, meta = desired_smtp({"host": "mail", "port": 1025, "security": "none"}, "", "", "dev@x", "http://h")
    assert (smtp["tls"], smtp["authMethod"], smtp["username"], meta["senderAddress"]) == (False, "", "", "dev@x")
    proton = {"host": "smtp.protonmail.ch", "port": 587, "security": "starttls"}
    assert desired_smtp(proton, "", "", "prod@x", "http://h") is None
    assert desired_smtp(proton, "alerts@x", "", "prod@x", "http://h") is None
    smtp, meta = desired_smtp(proton, "alerts@x", "token", "prod@x", "http://h")
    assert (smtp["tls"], smtp["authMethod"], meta["senderAddress"]) == (False, "PLAIN", "alerts@x")
    assert "password" not in smtp
    assert desired_smtp({"host": "mail", "port": 465, "security": "tls"}, "a@x", "t", "p@x", "u")[0]["tls"]
    print("beszel_config.py self-test OK")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--self-test", action="store_true")
    for name in ("base", "config", "compose-dir", "env", "system", "host", "port", "username", "app-url"):
        parser.add_argument(f"--{name}")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    missing = [name.replace("_", "-") for name, value in vars(args).items() if value is None]
    if missing:
        parser.error(f"missing --{', --'.join(missing)}")
    try:
        converge(args)
    except (HubError, OSError, KeyError, subprocess.CalledProcessError) as error:
        print(f"[beszel] FAIL {type(error).__name__}: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
