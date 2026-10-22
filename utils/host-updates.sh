#!/usr/bin/env bash
# List packages apt would upgrade. Exit 0 even when some are pending: this is
# a report, not a failed job. Diun already mails new image tags; it does not
# see apt or the VM image. No timer and no mail are wired here.
#
#   sudo ./utils/host-updates.sh

set -euo pipefail

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
