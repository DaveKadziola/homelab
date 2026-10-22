#!/usr/bin/env bash
# List packages apt would upgrade, and say when the published Ubuntu cloud
# image serial is newer than this guest. With --mail, send that once through
# the env SMTP relay and say nothing when both are current. Diun mails new
# container tags; it does not see apt or this image. A newer image is a VM
# rebuild, not an apt upgrade.
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
image_line=""
if [[ -r /etc/os-release && -r /etc/cloud/build.info ]] && command -v curl >/dev/null; then
  codename="$(awk -F= '/^VERSION_CODENAME=/{print $2}' /etc/os-release)"
  local_serial="$(awk -F'[=:] *' '/^serial/{print $2; exit}' /etc/cloud/build.info)"
  if [[ -n "$codename" && -n "$local_serial" ]]; then
    remote="$(curl -fsSL --max-time 20 "https://cloud-images.ubuntu.com/${codename}/current/unpacked/build-info.txt" || true)"
    remote_serial="$(printf '%s\n' "$remote" | awk -F= '/^serial=/{print $2; exit}')"
    if [[ -z "$remote_serial" ]]; then
      echo "cloud image serial: not fetched" >&2
    elif [[ "$remote_serial" != "$local_serial" ]]; then
      image_line="cloud image ${codename} serial ${local_serial} -> ${remote_serial} (rebuilding the VM, not apt)"
    fi
  fi
fi
report="$list"
if [[ -n "$image_line" ]]; then
  report="${report:+$report$'\n'}${image_line}"
fi
if [[ -z "$report" ]]; then
  echo "none"
  exit 0
fi
printf '%s\n' "$report"
[[ "$mail" == 1 ]] || exit 0

: "${HOMELAB_ENV:?HOMELAB_ENV is required for --mail}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export HOMELAB_CONFIG_DIR="${HOMELAB_CONFIG_DIR:-$ROOT/config}"
export HOMELAB_SECRETS_DIR="${HOMELAB_SECRETS_DIR:-$HOME/.homelab-secrets}"
export HOST_UPDATE_LIST="$report"
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
msg["Subject"] = f"homelab {env}: host updates"
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
