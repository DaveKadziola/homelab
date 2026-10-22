#!/usr/bin/env bash
# Mail stdin through the env SMTP relay. Empty stdin sends nothing.
# The Proxmox NIC cron calls this over SSH with a forced command, so the
# Proton secret stays on the apps host.
#
#   HOMELAB_ENV=prod HOMELAB_SECRETS_DIR=/opt/homelab/secrets ./utils/alert-mail.sh "nic errors"

set -euo pipefail

subject="${1:?usage: $0 <subject>}"
body="$(cat)"
[[ -n "${body//[[:space:]]/}" ]] || exit 0

: "${HOMELAB_ENV:?HOMELAB_ENV is required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export HOMELAB_CONFIG_DIR="${HOMELAB_CONFIG_DIR:-$ROOT/config}"
export HOMELAB_SECRETS_DIR="${HOMELAB_SECRETS_DIR:-$HOME/.homelab-secrets}"
export ALERT_SUBJECT="$subject"
export ALERT_BODY="$body"
python3 - <<'PY'
import os
import smtplib
import sys
from email.message import EmailMessage
from pathlib import Path

import yaml

env = os.environ["HOMELAB_ENV"]
config = Path(os.environ["HOMELAB_CONFIG_DIR"])
secrets = Path(os.environ["HOMELAB_SECRETS_DIR"]) / env
monitoring = yaml.safe_load((config / "monitoring.yml").read_text())
identities = yaml.safe_load((config / "identities.yml").read_text())
smtp = monitoring["environments"][env]["smtp"]
to = identities["environment_email"][env]
user = password = ""
user_path, pass_path = secrets / "SMTP_USERNAME", secrets / "SMTP_PASSWORD"
if user_path.is_file():
    user = user_path.read_text().strip()
if pass_path.is_file():
    password = pass_path.read_text().strip()
msg = EmailMessage()
msg["From"] = user or to
msg["To"] = to
msg["Subject"] = f"homelab {env}: {os.environ['ALERT_SUBJECT']}"
msg.set_content(os.environ["ALERT_BODY"] if os.environ["ALERT_BODY"].endswith("\n") else os.environ["ALERT_BODY"] + "\n")
try:
    with smtplib.SMTP(smtp["host"], int(smtp["port"]), timeout=30) as server:
        if smtp["security"] != "none":
            server.starttls()
            server.login(user, password)
        server.send_message(msg)
except Exception as exc:
    print(f"smtp failed: {type(exc).__name__}", file=sys.stderr)
    sys.exit(1)
print("mailed")
PY
