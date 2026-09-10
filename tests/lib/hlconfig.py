#!/usr/bin/env python3
"""Config reader for the homelab test suites (F7-C).

Every fact the tests use about a service comes from config/services.yml, and
every account/secret name from config/identities.yml. This module is the only
place that parses YAML, HCL (tfvars) and Markdown tables, so the bash suites
stay free of format details.

Commands that end in "check-" / "scan-" print result lines that the calling
suite feeds straight into report():

    STATUS<TAB>ID<TAB>MESSAGE

Everything else prints either KEY=VALUE lines (shell-eval friendly) or TSV.
Only pyyaml is required, which ships with the runner.

Usage: hlconfig.py <command> [args]
"""

from __future__ import annotations

import os
import re
import subprocess
import sys

import yaml

REPO = os.environ.get("HL_REPO_ROOT") or os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)

SERVICES_YML = os.path.join(REPO, "config", "services.yml")
IDENTITIES_YML = os.path.join(REPO, "config", "identities.yml")

# project name -> compose file, used to rebuild the container names compose
# would create (<project>-<service>-1) without talking to a Docker daemon.
COMPOSE_FILES = [
    os.path.join(REPO, "compose", "core", "docker-compose.yml"),
    os.path.join(REPO, "compose", "grocery", "docker-compose.yml"),
]

# Field separator for `services` records. Not a tab: tabs are IFS whitespace,
# so bash `read` collapses runs of them and empty fields would shift the
# columns of every service that omits `path`, `expect` or `profile`.
FIELD_SEP = "\x1f"

# Compose services that exist only to support another service and therefore
# have no entry of their own in config/services.yml.
COMPOSE_HELPERS = {
    "postgres-init",
    "immich-postgres",
    "immich-redis",
    "immich-machine-learning",
}


# --------------------------------------------------------------------------
# loading
# --------------------------------------------------------------------------
def load_yaml(path):
    with open(path, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def services_doc():
    return load_yaml(SERVICES_YML)


def identities_doc():
    return load_yaml(IDENTITIES_YML)


def out(status, ident, message):
    print(f"{status}\t{ident}\t{message}")


def fail_hard(message):
    print(f"hlconfig: {message}", file=sys.stderr)
    sys.exit(2)


# --------------------------------------------------------------------------
# env / services
# --------------------------------------------------------------------------
def inventory_facts(inventory_path):
    """Pull ansible_host/user/key for the first ubuntu_docker host."""
    facts = {}
    if not os.path.isfile(inventory_path):
        return facts
    with open(inventory_path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or line.startswith("["):
                continue
            for token in line.split():
                if "=" in token:
                    key, _, value = token.partition("=")
                    facts[key] = value
            if "ansible_host" in facts:
                break
    return facts


def cmd_env(env):
    doc = services_doc()
    envs = doc.get("environments") or {}
    if env not in envs:
        fail_hard(f"unknown environment '{env}' in config/services.yml")
    spec = envs[env]
    inventory = spec.get("inventory", "")
    inv_abs = os.path.join(REPO, inventory) if inventory else ""
    facts = inventory_facts(inv_abs)
    key = facts.get("ansible_ssh_private_key_file", "")
    if key.startswith("~"):
        key = os.path.expanduser(key)
    print(f"HL_HOST={spec.get('host', '')}")
    print(f"HL_SSH_USER={spec.get('ssh_user', facts.get('ansible_user', ''))}")
    print(f"HL_SSH_KEY={key}")
    print(f"HL_INVENTORY={inventory}")
    print(f"HL_INVENTORY_HOST={facts.get('ansible_host', '')}")
    print(f"HL_IDENTITY={spec.get('identity', '')}")


def service_rows():
    """config/services.yml as fixed-column TSV rows (see tests/README.md)."""
    rows = []
    for svc in services_doc().get("services") or []:
        expect = svc.get("expect") or []
        extra = svc.get("extra_ports") or []
        rows.append(
            [
                svc.get("name", ""),
                svc.get("priority", ""),
                svc.get("stack", ""),
                svc.get("container", ""),
                svc.get("check", ""),
                str(svc.get("port", "") or ""),
                svc.get("path", "") or "",
                ",".join(str(code) for code in expect),
                svc.get("profile", "") or "",
                "true" if svc.get("optional") else "false",
                ",".join(str(port) for port in extra),
                svc.get("public_url", "") or "",
            ]
        )
    return rows


def cmd_services(_env=None):
    for row in service_rows():
        print(FIELD_SEP.join(row))


# --------------------------------------------------------------------------
# secrets declared in config/identities.yml
# --------------------------------------------------------------------------
def expected_secrets(env):
    doc = identities_doc()
    names = {}
    for account in doc.get("accounts") or []:
        secret = account.get("secret")
        if not secret or env not in (account.get("envs") or []):
            continue
        names[secret] = f"account {account.get('app')}/{account.get('identity')}"
    for secret in doc.get("service_secrets") or []:
        name = secret.get("name")
        if not name or env not in (secret.get("envs") or []):
            continue
        # Issued by another app at bootstrap (e.g. Beszel hub key) — not a
        # GitHub secret until that bootstrap has run, so it is not required here.
        if secret.get("issued_by"):
            continue
        names[name] = "service secret for " + ",".join(secret.get("used_by") or [])
    return names


def cmd_secrets(env):
    for name, why in sorted(expected_secrets(env).items()):
        print(f"{name}\t{why}")


# --------------------------------------------------------------------------
# compose consistency
# --------------------------------------------------------------------------
def parse_host_port(entry):
    """'0.0.0.0:8101:8101' / '8083:80' / '22000:22000/udp' -> host port."""
    if isinstance(entry, dict):  # long syntax
        published = entry.get("published")
        return str(published) if published is not None else None
    text = str(entry).split("/")[0]
    parts = text.split(":")
    if len(parts) == 1:
        return None  # container-only port, not published on the host
    return parts[-2]


def compose_index():
    """container name -> {file, service, ports, profiles}."""
    index = {}
    for path in COMPOSE_FILES:
        if not os.path.isfile(path):
            continue
        doc = load_yaml(path) or {}
        project = doc.get("name") or os.path.basename(os.path.dirname(path))
        rel = os.path.relpath(path, REPO)
        for name, spec in (doc.get("services") or {}).items():
            spec = spec or {}
            ports = []
            for entry in spec.get("ports") or []:
                host_port = parse_host_port(entry)
                if host_port:
                    ports.append(host_port)
            index[f"{project}-{name}-1"] = {
                "file": rel,
                "service": name,
                "ports": sorted(set(ports), key=lambda p: int(p)),
                "profiles": spec.get("profiles") or [],
                "network_mode": spec.get("network_mode", ""),
            }
    return index


def cmd_check_compose():
    index = compose_index()
    if not index:
        out("SKIP", "compose/index", "no compose files found under compose/")
        return
    declared_containers = set()

    for row in service_rows():
        (
            name,
            _priority,
            stack,
            container,
            check,
            port,
            _path,
            _expect,
            profile,
            _optional,
            extra_ports,
            _public,
        ) = row
        ident = f"compose/{name}"
        if stack not in ("core", "grocery"):
            out("SKIP", ident, f"stack '{stack}' is not built from compose/")
            continue
        declared_containers.add(container)
        entry = index.get(container)
        if entry is None:
            out(
                "FAIL",
                ident,
                f"container '{container}' is not produced by any compose file "
                f"(expected <project>-<service>-1)",
            )
            continue

        problems = []
        wanted = [p for p in ([port] + extra_ports.split(",")) if p]
        if check == "container":
            # declared port is an internal listener (host network / exec-only)
            pass
        else:
            missing = [p for p in wanted if p not in entry["ports"]]
            if missing:
                problems.append(
                    f"port(s) {','.join(missing)} not published in {entry['file']} "
                    f"(published: {','.join(entry['ports']) or 'none'})"
                )
        compose_profile = entry["profiles"][0] if entry["profiles"] else ""
        if compose_profile != profile:
            problems.append(
                f"profile mismatch: services.yml='{profile or 'none'}' "
                f"compose='{compose_profile or 'none'}'"
            )
        if problems:
            out("FAIL", ident, "; ".join(problems))
        else:
            detail = f"{entry['file']} service '{entry['service']}'"
            if check == "container":
                detail += " (no published port expected)"
            elif wanted:
                detail += f" publishes {','.join(wanted)}"
            out("PASS", ident, detail)

    for container, entry in sorted(index.items()):
        if container in declared_containers or entry["service"] in COMPOSE_HELPERS:
            continue
        if not entry["ports"]:
            continue
        out(
            "FAIL",
            f"compose/undeclared/{entry['service']}",
            f"{entry['file']} publishes {','.join(entry['ports'])} but the container "
            f"'{container}' is missing from config/services.yml",
        )


# --------------------------------------------------------------------------
# docs consistency
# --------------------------------------------------------------------------
def normalise(text):
    return re.sub(r"[^a-z0-9]", "", text.lower())


def markdown_tables(path):
    """Yield (header_cells, [(line_no, row_cells)]) for every table in a file."""
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()
    i = 0
    while i < len(lines):
        if lines[i].lstrip().startswith("|") and i + 1 < len(lines):
            separator = lines[i + 1].strip()
            if re.fullmatch(r"\|[\s:|-]+\|", separator):
                header = [c.strip() for c in lines[i].strip().strip("|").split("|")]
                rows = []
                j = i + 2
                while j < len(lines) and lines[j].lstrip().startswith("|"):
                    rows.append(
                        (j + 1, [c.strip() for c in lines[j].strip().strip("|").split("|")])
                    )
                    j += 1
                yield header, rows
                i = j
                continue
        i += 1


def doc_files():
    paths = []
    docs_dir = os.path.join(REPO, "docs")
    if os.path.isdir(docs_dir):
        for name in sorted(os.listdir(docs_dir)):
            if name.endswith(".md"):
                paths.append(os.path.join(docs_dir, name))
    readme = os.path.join(REPO, "README.md")
    if os.path.isfile(readme):
        paths.append(readme)
    return paths


def cmd_check_docs():
    doc = services_doc()
    keys = {}
    for svc in doc.get("services") or []:
        for label in (svc.get("name", ""), svc.get("title", "")):
            if label:
                keys[normalise(label)] = svc["name"]
    by_name = {svc["name"]: svc for svc in doc.get("services") or []}
    found = {name: [] for name in by_name}

    for path in doc_files():
        rel = os.path.relpath(path, REPO)
        for header, rows in markdown_tables(path):
            # A service port table has both a port column and a column naming
            # the service; anything else (firewall rules, capacity tables) is
            # not something config/services.yml can be compared against.
            port_cols = [i for i, cell in enumerate(header) if re.search(r"\bport", cell, re.I)]
            name_cols = [
                i
                for i, cell in enumerate(header)
                if re.search(r"\b(service|app|application|name|container)\b", cell, re.I)
            ]
            if not port_cols or not name_cols:
                continue
            for line_no, cells in rows:
                matched = None
                for col in name_cols:
                    if col >= len(cells):
                        continue
                    norm = normalise(cells[col])
                    if not norm:
                        continue
                    for key, name in keys.items():
                        if key and key in norm:
                            if matched is None or len(key) > len(matched[1]):
                                matched = (name, key)
                if matched is None:
                    continue
                ports = set()
                for col in port_cols:
                    if col < len(cells):
                        ports.update(re.findall(r"\d{2,5}", cells[col]))
                found[matched[0]].append((f"{rel}:{line_no}", ports))

    for name, svc in by_name.items():
        ident = f"docs/{name}"
        hits = found[name]
        if not hits:
            out("SKIP", ident, "not listed in any markdown port table")
            continue
        declared = {str(p) for p in [svc.get("port")] if p}
        declared |= {str(p) for p in svc.get("extra_ports") or []}
        bad = []
        for where, ports in hits:
            if not declared:
                if ports:
                    bad.append(f"{where} lists port(s) {','.join(sorted(ports))} but "
                               f"config/services.yml declares none")
                continue
            if not declared & ports:
                bad.append(
                    f"{where} lists {','.join(sorted(ports)) or 'no port'} "
                    f"instead of {','.join(sorted(declared))}"
                )
        if bad:
            out("FAIL", ident, "; ".join(bad))
        else:
            out("PASS", ident, f"{', '.join(where for where, _ in hits)} agree with config")


# --------------------------------------------------------------------------
# committed-secret scan (gitleaks stand-in)
# --------------------------------------------------------------------------
PLACEHOLDER_WORDS = (
    "change-me",
    "changeme",
    "change_me",
    "example",
    "placeholder",
    "your-",
    "redacted",
    "xxxx",
    "todo",
    "none",
    "null",
    "true",
    "false",
    "dev-only",
)

HASH_PREFIXES = ("$argon2", "$2y$", "$2a$", "$6$", "$5$", "$1$", "$pbkdf2")

TOKEN_PATTERNS = [
    ("github token", re.compile(r"gh[pousr]_[A-Za-z0-9]{36,}")),
    ("github pat", re.compile(r"github_pat_[A-Za-z0-9_]{22,}")),
    ("aws access key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("slack token", re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}")),
    ("private key block", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
]

SECRET_WORDS = ("PASSWORD", "PASSWD", "SECRET", "TOKEN", "APIKEY", "KEY")

ASSIGNMENT = re.compile(
    r"(?<![A-Za-z0-9_])(?P<key>[A-Za-z_][A-Za-z0-9_]*)"
    r"\s*[:=]\s*(?P<quote>['\"]?)(?P<value>[^\s'\"#,}]{8,})"
)

# `${FOO_PASSWORD:-literal}` in compose — the literal is what a deploy without
# the secret actually uses.
COMPOSE_DEFAULT = re.compile(
    r"\$\{(?P<key>[A-Za-z_][A-Za-z0-9_]*)\s*:-\s*(?P<value>[^}]*)\}"
)

# `FOO_SECRET={{ lookup('env', 'X') | default('literal', true) }}` in Ansible.
JINJA_DEFAULT = re.compile(
    r"(?<![A-Za-z0-9_])(?P<key>[A-Za-z_][A-Za-z0-9_]*)\s*[:=]\s*\{\{"
    r"[^}]*default\(\s*'(?P<value>[^']{4,})'"
)


def is_secret_key(key):
    upper = key.upper()
    return any(word in upper for word in SECRET_WORDS)


def value_is_reference(value):
    """True for anything that is not a literal secret: vars, paths, hashes."""
    if value.startswith(("${", "{{", "<", "$(", "!ENV", "~", "/", "./")):
        return True
    if value.startswith(HASH_PREFIXES):
        return True
    if "/" in value or value.endswith((".pem", ".crt", ".key", ".yml", ".yaml", ".json")):
        return True
    if re.fullmatch(r"[a-z0-9_.-]*(_password|_secret|_key|_token)", value.lower()):
        return True  # a variable name being passed along
    return False


def looks_like_secret_value(value):
    """Heuristic stand-in for gitleaks entropy rules — see tests/README.md."""
    if len(value) < 12:
        return False
    if any(char in value for char in "()[]{}<>/\\$=`|"):
        return False  # code, a path or a variable reference, not a literal
    if not any(char.isdigit() for char in value):
        return False
    if not any(char.isalpha() for char in value):
        return False
    return True

# This file necessarily contains the patterns above; scanning it would always hit.
SCAN_EXCLUDE = {"tests/lib/hlconfig.py"}

DEPLOYED_PATH_PREFIXES = ("compose/", "ansible/")


def tracked_files():
    result = subprocess.run(
        ["git", "-C", REPO, "ls-files"], capture_output=True, text=True, check=False
    )
    if result.returncode != 0:
        return []
    return [line for line in result.stdout.splitlines() if line]


def is_repeated(value):
    """'0123456789abcdef' x4 and friends -> obvious filler, not a real secret."""
    length = len(value)
    for unit in range(1, length // 2 + 1):
        if length % unit == 0 and value == value[:unit] * (length // unit):
            return True
    return False


def looks_like_placeholder(value):
    low = value.lower()
    if any(word in low for word in PLACEHOLDER_WORDS):
        return True
    if value.startswith(("${", "{{", "<", "$(", "!ENV")):
        return True
    if value.startswith(HASH_PREFIXES):  # password hash, not a plaintext secret
        return True
    if is_repeated(low.strip("'\"")):
        return True
    if re.fullmatch(r"[A-Za-z0-9_./-]*(\.pem|\.key|\.crt|\.yml|\.yaml|\.json)", value):
        return True
    if re.fullmatch(r"[a-z0-9_.-]*(_password|_secret|_key|_token)", low):
        return True  # a variable/lookup name, not a value
    return False


def read_lines(rel):
    path = os.path.join(REPO, rel)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return fh.read().splitlines()
    except (UnicodeDecodeError, OSError):
        return []


def default_credential_hits(rel, line_no, line):
    """Literal secret values a deploy would actually use if the secret is unset."""
    hits = []
    base = os.path.basename(rel)
    if not rel.startswith(DEPLOYED_PATH_PREFIXES) or base.endswith(".example"):
        return hits
    if line.strip().startswith("#"):
        return hits

    for match in COMPOSE_DEFAULT.finditer(line):
        key, value = match.group("key"), match.group("value").strip()
        if value and is_secret_key(key) and not value_is_reference(value):
            hits.append(f"{key} (line {line_no})")

    for match in JINJA_DEFAULT.finditer(line):
        key, value = match.group("key"), match.group("value").strip()
        if value and is_secret_key(key) and not value_is_reference(value):
            hits.append(f"{key} (line {line_no})")

    for match in ASSIGNMENT.finditer(line):
        key, value = match.group("key"), match.group("value")
        if not is_secret_key(key) or value_is_reference(value):
            continue
        if f"{key} (line {line_no})" not in hits:
            hits.append(f"{key} (line {line_no})")
    return hits


def cmd_scan_secrets():
    files = tracked_files()
    if not files:
        out("SKIP", "secret-scan/tracked-files", "git ls-files returned nothing")
        return

    token_hits, assignment_hits, env_hits, default_hits = [], [], [], {}

    for rel in files:
        if rel in SCAN_EXCLUDE:
            continue
        base = os.path.basename(rel)
        if base == ".env" or (base.startswith(".env.") and not base.endswith(".example")):
            env_hits.append(rel)
        for line_no, line in enumerate(read_lines(rel), start=1):
            for label, pattern in TOKEN_PATTERNS:
                if pattern.search(line):
                    token_hits.append(f"{rel}:{line_no} ({label})")
            for hit in default_credential_hits(rel, line_no, line):
                default_hits.setdefault(rel, []).append(hit)
            for match in ASSIGNMENT.finditer(line):
                key, value = match.group("key"), match.group("value")
                if not is_secret_key(key):
                    continue
                if not looks_like_secret_value(value) or looks_like_placeholder(value):
                    continue
                assignment_hits.append(f"{rel}:{line_no} ({key})")

    if token_hits:
        out("FAIL", "secret-scan/tokens", "; ".join(sorted(set(token_hits))[:10]))
    else:
        out("PASS", "secret-scan/tokens", f"no keys/tokens in {len(files)} tracked files")

    if assignment_hits:
        out("FAIL", "secret-scan/values", "; ".join(sorted(set(assignment_hits))[:10]))
    else:
        out("PASS", "secret-scan/values", "no high-entropy secret assignments committed")

    if env_hits:
        out("FAIL", "secret-scan/env-files", "tracked env file(s): " + ", ".join(env_hits))
    else:
        out("PASS", "secret-scan/env-files", "no .env file is tracked (only .env.example)")

    if default_hits:
        for rel, keys in sorted(default_hits.items()):
            out(
                "FAIL",
                f"default-credentials/{rel}",
                "deployed file carries a literal default value for "
                + ", ".join(keys)
                + " — must come from the GitHub environment secret",
            )
    else:
        out("PASS", "default-credentials", "no default secret values in compose/ or ansible/")


# --------------------------------------------------------------------------
# tfvars (HCL) — enough parsing for vm_config.<vm>
# --------------------------------------------------------------------------
def tfvars_path(env):
    return os.path.join(REPO, "terraform", "environments", env, "terraform.tfvars")


def tfvars_block(text, header_regex):
    match = re.search(header_regex, text)
    if not match:
        return None
    start = text.index("{", match.start())
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1 : i]
    return None


def tfvars_vm(env, vm):
    path = tfvars_path(env)
    if not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    vm_config = tfvars_block(text, r"vm_config\s*=\s*")
    if vm_config is None:
        return None
    block = tfvars_block(vm_config, rf"(?m)^\s*{re.escape(vm)}\s*=\s*")
    if block is None:
        return None
    values = {}
    for line in block.splitlines():
        line = line.split("#")[0].strip()
        match = re.match(r"^([a-z_]+)\s*=\s*(.+)$", line)
        if match:
            values[match.group(1)] = match.group(2).strip().strip(",").strip('"')
    return values


def cmd_tfvars(env, vm):
    values = tfvars_vm(env, vm)
    if values is None:
        fail_hard(f"no vm_config.{vm} in {tfvars_path(env)}")
    mapping = {
        "TF_RAM": "ram",
        "TF_CPU_CORES": "cpu_cores",
        "TF_CPU_TYPE": "cpu_type",
        "TF_STORAGE_SIZE": "storage_size",
        "TF_CIDR": "cloud_init_cidr",
        "TF_GATEWAY": "cloud_init_gateway",
        "TF_DNS": "cloud_init_dns",
        "TF_VLAN_TAG": "vlan_tag",
        "TF_VM_ID": "vm_id",
        "TF_VM_NAME": "vm_name",
    }
    for shell_name, key in mapping.items():
        print(f"{shell_name}={values.get(key, '')}")


# --------------------------------------------------------------------------
# network facts vs docs/network.md
# --------------------------------------------------------------------------
def docs_network_text():
    path = os.path.join(REPO, "docs", "network.md")
    if not os.path.isfile(path):
        return ""
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def cmd_check_network(env):
    doc = services_doc()
    spec = (doc.get("environments") or {}).get(env) or {}
    host = spec.get("host", "")
    inventory = os.path.join(REPO, spec.get("inventory", ""))
    inv_host = inventory_facts(inventory).get("ansible_host", "")
    tf = tfvars_vm(env, "apps") or {}
    tf_ip = (tf.get("cloud_init_cidr", "") or "").split("/")[0]
    tf_prefix = (tf.get("cloud_init_cidr", "") or "/").split("/")[-1]
    network_md = docs_network_text()

    if not host:
        out("FAIL", "network/host-ip", f"config/services.yml has no host for env {env}")
        return

    if inv_host == host:
        out("PASS", "network/inventory", f"{spec.get('inventory')} ansible_host == {host}")
    else:
        out(
            "FAIL",
            "network/inventory",
            f"{spec.get('inventory')} ansible_host='{inv_host}' != services.yml host='{host}'",
        )

    if not tf_ip:
        out("SKIP", "network/tfvars-ip", f"no vm_config.apps.cloud_init_cidr for {env}")
    elif tf_ip == host:
        out("PASS", "network/tfvars-ip", f"terraform cloud_init_cidr {tf.get('cloud_init_cidr')}")
    else:
        out(
            "FAIL",
            "network/tfvars-ip",
            f"terraform cloud_init_cidr '{tf.get('cloud_init_cidr')}' != services.yml '{host}'",
        )

    if not network_md:
        out("SKIP", "network/docs-ip", "docs/network.md not found")
    elif host in network_md:
        out("PASS", "network/docs-ip", f"docs/network.md documents {host}")
    else:
        out("FAIL", "network/docs-ip", f"{host} is not documented in docs/network.md")

    gateway = tf.get("cloud_init_gateway", "")
    if not gateway:
        out("SKIP", "network/docs-gateway", "no cloud_init_gateway in tfvars")
    elif gateway in network_md:
        out("PASS", "network/docs-gateway", f"gateway {gateway} matches docs/network.md")
    else:
        out(
            "FAIL",
            "network/docs-gateway",
            f"gateway {gateway} from tfvars is not in docs/network.md",
        )

    vlan = tf.get("vlan_tag", "")
    if not vlan:
        out(
            "SKIP",
            "network/docs-vlan",
            f"env {env} has no vlan_tag (flat network) — nothing to compare",
        )
    else:
        pattern = re.compile(rf"\|\s*APP\s*\|\s*{re.escape(vlan)}\s*\|")
        if pattern.search(network_md):
            out("PASS", "network/docs-vlan", f"APP VLAN tag {vlan} matches docs/network.md")
        else:
            out(
                "FAIL",
                "network/docs-vlan",
                f"tfvars vlan_tag={vlan} not found as the APP VLAN row in docs/network.md",
            )

    if tf_prefix and tf_prefix != "/":
        subnet_hint = f"/{tf_prefix}"
        if subnet_hint in network_md:
            out("PASS", "network/docs-prefix", f"prefix {subnet_hint} appears in docs/network.md")
        else:
            out(
                "FAIL",
                "network/docs-prefix",
                f"prefix {subnet_hint} from tfvars is not in docs/network.md",
            )


# --------------------------------------------------------------------------
# ansible --check output
# --------------------------------------------------------------------------
def cmd_ansible_changed():
    """Read ansible-playbook --check output on stdin, print changed task names."""
    task = ""
    changed = []
    for line in sys.stdin:
        match = re.match(r"^TASK \[(.+)\]", line)
        if match:
            task = match.group(1)
            continue
        if line.startswith("changed:") and task:
            if task not in changed:
                changed.append(task)
    for name in changed:
        print(name)


# --------------------------------------------------------------------------
COMMANDS = {
    "env": cmd_env,
    "services": cmd_services,
    "secrets": cmd_secrets,
    "check-compose": cmd_check_compose,
    "check-docs": cmd_check_docs,
    "check-network": cmd_check_network,
    "scan-secrets": cmd_scan_secrets,
    "tfvars": cmd_tfvars,
    "ansible-changed": cmd_ansible_changed,
}


def main(argv):
    if len(argv) < 2 or argv[1] not in COMMANDS:
        print(__doc__, file=sys.stderr)
        print("commands: " + ", ".join(sorted(COMMANDS)), file=sys.stderr)
        return 2
    try:
        COMMANDS[argv[1]](*argv[2:])
    except TypeError as exc:
        fail_hard(f"{argv[1]}: {exc}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
