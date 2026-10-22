#!/usr/bin/env bash
# List packages apt would upgrade. With --mail, send that list once through the
# env SMTP relay and say nothing when there is nothing to upgrade. Diun already
# mails new image tags; it does not see apt or the VM image.
#
#   sudo ./utils/host-updates.sh
#   HOMELAB_ENV=dev HOMELAB_SECRETS_DIR=/opt/homelab/secrets ./utils/host-updates.sh --mail

set -euo pipefail

mail=0
if [[ "${1:-}" == "--mail" ]]; then
  mail=1
elif [[ -n "${1:-}" ]]; then
  echo "usage: $0 [--mail]" >&2
  exit 2
fi

if ! command -v apt-get >/dev/null; then
  echo "apt-get not found" >&2
  exit 2
fi

list="$(apt-get -s upgrade 2>/dev/null | awk '/^Inst /{print $2}')"
if [[ -z "$list" ]]; then
  echo "none"
  exit 0
fi
printf '%s\n' "$list"
[[ "$mail" == 1 ]] || exit 0

: "${HOMELAB_ENV:?HOMELAB_ENV is required for --mail}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export HOMELAB_CONFIG_DIR="${HOMELAB_CONFIG_DIR:-$ROOT/config}"
export HOMELAB_SECRETS_DIR="${HOMELAB_SECRETS_DIR:-$HOME/.homelab-secrets}"
export HOST_UPDATE_LIST="$list"
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
sender = user or to
msg = EmailMessage()
msg["From"] = sender
msg["To"] = to
msg["Subject"] = f"homelab {env}: apt updates"
msg.set_content(os.environ["HOST_UPDATE_LIST"] + "\n")
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
