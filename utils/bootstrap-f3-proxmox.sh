#!/usr/bin/env bash
# Bootstrap F3 — prepare the prod Proxmox host and set its API URL in GitHub prod (no secrets
# generated here).
#
# Prerequisites: Proxmox online, API token created (docs/f3-proxmox.md F3-02).
#
# Usage:
#   PROXMOX_IP=192.168.20.20 [PVE_KEY=~/.ssh/<root key>] ./utils/bootstrap-f3-proxmox.sh [--dry-run]
#   ./utils/bootstrap-f3-proxmox.sh --upgrade     # also apt-get dist-upgrade (no reboot)
#   ./utils/bootstrap-f3-proxmox.sh --set-token   # also prompt for the token secret; it replaces
#     GH prod, ~/.homelab-secrets/prod/ and Bitwarden (utils/bw-store.py, queued while locked)
#
# On the host: snippets on datastore `local`; the post-install steps of the community
# post-pve-install script (pve-no-subscription instead of the enterprise repositories, no
# subscription notice in the web UI, HA services off on a single node) without its prompts and
# telemetry. Handles deb822 sources (PVE 9) only. --dry-run changes nothing, on the host or in
# GitHub.

set -euo pipefail

REPO="${GITHUB_REPO:-DaveKadziola/homelab}"
PROXMOX_IP="${PROXMOX_IP:-192.168.20.20}"
API_URL="https://${PROXMOX_IP}:8006/api2/json"
SET_TOKEN=false
DRY_RUN=0
UPGRADE=0

for arg in "$@"; do
  case "$arg" in
    --set-token) SET_TOKEN=true ;;
    --dry-run) DRY_RUN=1 ;;
    --upgrade) UPGRADE=1 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

command -v gh >/dev/null || { echo "gh required"; exit 1; }

{ echo "DRY=$DRY_RUN UPGRADE=$UPGRADE"; cat <<'REMOTE'; } | ssh -o BatchMode=yes ${PVE_KEY:+-i "$PVE_KEY"} "root@${PROXMOX_IP}" 'sh -s'
set -eu

# Terraform uploads the cloud-init user data as a snippet to datastore `local`; a fresh PVE
# install does not allow that content type there.
cur=$(awk '/^dir: local$/{f=1;next} f&&/^\tcontent /{print $2; exit}' /etc/pve/storage.cfg)
case ",$cur," in
  *,snippets,*) echo "ok    local allows snippets" ;;
  *) if [ "$DRY" = 1 ]; then echo "would enable snippets on local"
     else pvesm set local --content "$cur,snippets"; echo "local: snippets enabled"; fi ;;
esac

# Without a subscription the enterprise repositories answer 401, so the host gets no updates
# until pve-no-subscription is configured.
if ls /etc/apt/sources.list.d/*.list >/dev/null 2>&1; then
  echo "STOP: .list files in /etc/apt/sources.list.d - only deb822 sources (PVE 9) are handled"
  exit 1
fi
for f in /etc/apt/sources.list.d/*.sources; do
  grep -q 'enterprise\.proxmox\.com' "$f" || continue
  [ "$(grep -c '^Types:' "$f")" = 1 ] || { echo "STOP: $f has more than one stanza"; exit 1; }
  if grep -q '^Enabled: *no$' "$f"; then echo "ok    $f disabled"
  elif [ "$DRY" = 1 ]; then echo "would disable $f"
  else sed -i '/^Enabled:/d; /^Types:/a Enabled: no' "$f"; echo "disabled $f"; fi
done
nosub=/etc/apt/sources.list.d/proxmox.sources
want="Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg"
if [ -f "$nosub" ] && [ "$(cat "$nosub")" = "$want" ]; then echo "ok    $nosub"
elif [ "$DRY" = 1 ]; then echo "would write $nosub (pve-no-subscription)"
else printf '%s\n' "$want" > "$nosub"; echo "wrote $nosub"; fi

# Subscription notice in the web UI. dpkg runs the hook after every package change, because an
# update of proxmox-widget-toolkit restores the original file.
hook=/usr/local/bin/pve-remove-nag.sh
apt_hook=/etc/apt/apt.conf.d/no-nag-script
tmp=$(mktemp)
cat > "$tmp" <<'HOOK'
#!/bin/sh
# From homelab utils/bootstrap-f3-proxmox.sh: hides the "No valid subscription" notice.
js=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
[ -s "$js" ] || exit 0
grep -q NoMoreNagging "$js" ||
  sed -i "s/res\.data\.status\.toLowerCase() !== 'active'/res.data.status.toLowerCase() === 'NoMoreNagging'/" "$js"
exit 0
HOOK
if cmp -s "$tmp" "$hook" && grep -qs "$hook" "$apt_hook"; then echo "ok    $hook and $apt_hook"
elif [ "$DRY" = 1 ]; then echo "would install $hook and $apt_hook"
else
  install -m 755 "$tmp" "$hook"
  printf 'DPkg::Post-Invoke { "%s"; };\n' "$hook" > "$apt_hook"
  echo "installed $hook and $apt_hook"
fi
rm -f "$tmp"
[ "$DRY" = 1 ] || "$hook"
if grep -q NoMoreNagging /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; then
  echo "ok    subscription notice hidden (reload the browser without cache)"
else
  echo "subscription notice still shown"
fi

# HA services only act in a cluster; on a single node they only cost resources.
if [ -e /etc/pve/corosync.conf ]; then
  echo "ok    cluster node - HA services left as they are"
else
  for s in pve-ha-lrm pve-ha-crm; do
    if ! systemctl -q is-enabled "$s" && ! systemctl -q is-active "$s"; then echo "ok    $s off"
    elif [ "$DRY" = 1 ]; then echo "would disable and stop $s (single node)"
    else systemctl -q disable --now "$s"; echo "disabled $s"; fi
  done
fi

[ "$DRY" = 1 ] && { echo "dry run - nothing changed on the host"; exit 0; }
apt-get update -q >/dev/null
echo "ok    apt-get update; upgradable: $(apt list --upgradable 2>/dev/null | grep -c /)"
if [ "$UPGRADE" = 1 ]; then
  DEBIAN_FRONTEND=noninteractive apt-get -y -q \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold dist-upgrade
  newest=$(ls /boot/vmlinuz-* | sed 's|^/boot/vmlinuz-||' | sort -V | tail -1)
  if [ "$newest" = "$(uname -r)" ]; then echo "ok    running the newest kernel $newest"
  else echo "REBOOT NEEDED: running $(uname -r), installed $newest"; fi
fi
REMOTE

if [[ $DRY_RUN == 1 ]]; then
  echo "dry run - GitHub variable PROXMOX_API_URL not set (would be $API_URL)"
  exit 0
fi

echo "Proxmox API URL: $API_URL"
gh variable set PROXMOX_API_URL --env prod --repo "$REPO" --body "$API_URL"
echo "set variable PROXMOX_API_URL (prod)"

if $SET_TOKEN; then
  echo "Paste API token secret (input hidden):"
  read -rs TOKEN
  printf '%s' "$TOKEN" | gh secret set PROXMOX_API_TOKEN_SECRET --env prod --repo "$REPO"
  printf '%s' "$TOKEN" | "$(dirname "${BASH_SOURCE[0]}")/bw-store.py" --env prod --stdin PROXMOX_API_TOKEN_SECRET
  unset TOKEN
  echo "set secret PROXMOX_API_TOKEN_SECRET (prod)"
fi

echo ""
echo "Next:"
echo "  1. ./utils/f3-verify.sh"
echo "  2. terraform plan/apply — docs/f3-proxmox.md"
