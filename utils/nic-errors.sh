#!/usr/bin/env bash
# Print receive error counters for every interface except lo.
# With --check, exit 1 when rx_crc_errors, rx_errors or rx_dropped grew since
# the state file. The first --check only stores the counters.
# Prod cron mails only when a counter grew. Cumulative crc on nic1 stays
# high, so a check for "non-zero" would never stop.
#
#   ./utils/nic-errors.sh
#   ./utils/nic-errors.sh --check /var/lib/homelab/nic-errors.prev

set -euo pipefail

state=""
if [[ "${1:-}" == "--check" ]]; then
  state="${2:-}"
  [[ -n "$state" ]] || { echo "usage: $0 --check <state-file>" >&2; exit 2; }
fi

fail=0
now=""
for dir in /sys/class/net/*; do
  name="$(basename "$dir")"
  [[ "$name" == lo ]] && continue
  [[ -r "$dir/statistics/rx_crc_errors" ]] || continue
  crc="$(cat "$dir/statistics/rx_crc_errors")"
  rx="$(cat "$dir/statistics/rx_errors")"
  drop="$(cat "$dir/statistics/rx_dropped")"
  echo "$name crc=$crc rxerr=$rx drop=$drop"
  now+="$name $crc $rx $drop"$'\n'
done

if [[ -z "$state" ]]; then
  exit 0
fi

if [[ ! -f "$state" ]]; then
  mkdir -p "$(dirname "$state")"
  printf '%s' "$now" > "$state"
  echo "stored $state"
  exit 0
fi

while read -r name crc rx drop; do
  [[ -n "$name" ]] || continue
  prev="$(awk -v n="$name" '$1==n {print $2, $3, $4}' "$state")"
  [[ -n "$prev" ]] || continue
  read -r pc pr pd <<<"$prev"
  if (( crc > pc || rx > pr || drop > pd )); then
    echo "grew $name crc $pc->$crc rxerr $pr->$rx drop $pd->$drop" >&2
    fail=1
  fi
done <<<"$now"

printf '%s' "$now" > "$state"
exit "$fail"
