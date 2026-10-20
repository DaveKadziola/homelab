#!/usr/bin/env bash
# Prod CI runner (label homelab-prod) in an LXC container on the physical Proxmox host.
#
#   ./utils/pve-ci-runner-lxc.sh --dry-run   # show what would change
#   ./utils/pve-ci-runner-lxc.sh             # create or converge, register, check
#
# Not in the prod Terraform state on purpose: Infra Apply Prod runs on this runner, and an apply
# that replaced its own runner would end the job half way. An existing container is started and
# converged, never recreated.
# Hardening: unprivileged; IOT VLAN 20 next to the hosts it deploys; no SSH server (on the host:
# pct enter 110); nftables drops every inbound packet, the runner only dials out; the runner runs
# as user "runner" without sudo.

set -euo pipefail
# ${BASH_SOURCE[0]:-$0}: the file also runs as `bash -s` inside the container, without a source path.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
PVE_HOST="${PVE_HOST:-192.168.20.20}"
PVE_KEY="${PVE_KEY:-$HOME/.ssh/homelab_prod_pve_ed25519}"
REPO="${GITHUB_REPO:-DaveKadziola/homelab}"
CTID="${CTID:-110}"
CT_NAME=ci-runner
CT_IP=192.168.20.14
GATEWAY=192.168.20.1
# Debian 13 like the laptop runner it replaces: the same apt Ansible.
TEMPLATE=debian-13-standard_13.6-1_amd64.tar.zst
RUNNER_NAME=homelab-prod-ci-runner
RUNNER_DIR=/home/runner/actions-runner
LIB=/usr/local/lib/homelab

# Runs inside the container as root: the host part streams this file to `bash -s -- --inside`.
inside() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -q
  # The template ages; unattended-upgrades keeps Debian security fixes coming on a host that runs 24/7.
  apt-get upgrade -y -q
  apt-get install -y -q --no-install-recommends unattended-upgrades
  # ansible with its recommends, as on the laptop; then what the workflows and tests call; then the
  # runner's .NET libraries (what its bin/installdependencies.sh picks on Debian 13).
  apt-get install -y -q ansible
  apt-get install -y -q --no-install-recommends bind9-dnsutils ca-certificates curl gh git jq \
    nftables openssh-client openssl python3-yaml unzip \
    libicu76 libkrb5-3 liblttng-ust1t64 libssl3t64 zlib1g
  if dpkg -s openssh-server >/dev/null 2>&1; then
    apt-get purge -y -q openssh-server
    apt-get autoremove -y -q
  fi
  cat >/etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
# Written by utils/pve-ci-runner-lxc.sh. Nothing here serves the network: the runner only dials out.
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority filter; policy drop;
    iif lo accept
    ct state established,related accept
    meta l4proto { icmp, ipv6-icmp } accept
  }
}
EOF
  systemctl enable -q nftables
  systemctl restart nftables
  id runner >/dev/null 2>&1 || useradd --create-home --shell /bin/bash runner
  chmod 700 /home/runner
  install -d -m 755 "$LIB"
}

# Runs inside the container: the endpoints the prod jobs dial, and the tools they call.
check_inside() {
  local rc=0 t
  for t in github.com:443 api.github.com:443 app.terraform.io:443 releases.hashicorp.com:443 \
    "${PVE_HOST}:8006" "${PVE_HOST}:22" 192.168.20.12:22 192.168.50.30:22; do
    if timeout 5 bash -c "exec 3<>/dev/tcp/${t%:*}/${t#*:}" 2>/dev/null; then
      echo "ok   reach $t"
    else
      echo "FAIL reach $t"; rc=1
    fi
  done
  for t in ansible-playbook git jq dig openssl gh unzip ssh python3; do
    command -v "$t" >/dev/null && echo "ok   tool $t" || { echo "FAIL tool $t"; rc=1; }
  done
  python3 -c 'import yaml' && echo "ok   python3-yaml" || { echo "FAIL python3-yaml"; rc=1; }
  # With the runner service's own LANG: a locale the container lacks stops every Ansible step.
  t="$(sed -n 's/^LANG=//p' "$RUNNER_DIR/.env" 2>/dev/null)"
  if env -i PATH=/usr/bin:/bin LANG="$t" ansible --version >/dev/null 2>&1; then echo "ok   ansible runs with LANG=$t"; else echo "FAIL ansible with the runner's LANG='$t'"; rc=1; fi
  t="$(ss -Htln | awk '$4 !~ /^(127\.|\[::1\])/ {print $4}' | paste -sd' ')"
  if [[ -n "$t" ]]; then echo "FAIL listening beyond loopback: $t"; rc=1; else echo "ok   nothing listens beyond loopback"; fi
  return "$rc"
}

case "${1:-}" in
  --inside) inside; exit 0 ;;
  --check-inside) check_inside; exit ;;
  --dry-run) DRY_RUN=true ;;
  "") DRY_RUN=false ;;
  -h | --help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "unknown option: $1" >&2; exit 1 ;;
esac

# Arguments are quoted for the remote shell, so values with spaces survive ssh.
pve() { ssh -o BatchMode=yes -o ConnectTimeout=10 -o SetEnv=LC_ALL=C -i "$PVE_KEY" "root@${PVE_HOST}" "$(printf '%q ' "$@")"; }
change() { if $DRY_RUN; then echo "would: $*"; else pve "$@"; fi; }
ct() { pve pct exec "$CTID" -- "$@"; }

echo "== template $TEMPLATE"
# grep without -q reads to the end: an early exit would fail the pipe under pipefail.
if pve pveam list local | grep -F "$TEMPLATE" >/dev/null; then echo "present"; else change pveam download local "$TEMPLATE"; fi

echo "== container $CTID ($CT_NAME, $CT_IP)"
if pve pct config "$CTID" >/dev/null 2>&1; then
  have="$(pve pct config "$CTID" | awk '/^hostname:/ {print $2}')"
  [[ "$have" == "$CT_NAME" ]] || { echo "CT $CTID exists as '$have', not $CT_NAME - stop" >&2; exit 1; }
  echo "present"
else
  if pve ping -c1 -W1 "$CT_IP" >/dev/null 2>&1; then echo "$CT_IP answers ping - in use, stop" >&2; exit 1; fi
  # Memory and cores are limits, not reservations: idle, the container uses what it needs.
  change pct create "$CTID" "local:vztmpl/$TEMPLATE" --hostname "$CT_NAME" --ostype debian \
    --unprivileged 1 --features nesting=1 --cores 2 --memory 2048 --swap 512 --rootfs local-lvm:8 \
    --net0 "name=eth0,bridge=vmbr0,tag=20,ip=${CT_IP}/24,gw=${GATEWAY}" --nameserver "$GATEWAY" \
    --onboot 1 --description "GitHub runner homelab-prod - utils/pve-ci-runner-lxc.sh"
fi
if [[ "$(pve pct status "$CTID" 2>/dev/null)" != "status: running" ]]; then change pct start "$CTID"; fi
$DRY_RUN && { echo "would: converge packages, nftables, user runner; register $RUNNER_NAME; check"; exit 0; }

for _ in $(seq 30); do ct getent hosts deb.debian.org >/dev/null 2>&1 && break; sleep 2; done

echo "== packages, nftables, user runner"
ct bash -s -- --inside <"$0"

echo "== runner $RUNNER_NAME"
if ct test -f "$RUNNER_DIR/.runner"; then
  echo "registered"
else
  ct tee "$LIB/setup-github-runner.sh" <"$ROOT/utils/setup-github-runner.sh" >/dev/null
  # The registration token goes through stdin: never on a laptop or host command line, never in a log.
  gh api -X POST "repos/${REPO}/actions/runners/registration-token" --jq .token |
    ct runuser -u runner -- env RUNNER_INSTALL_DIR="$RUNNER_DIR" GITHUB_REPO="$REPO" \
      bash "$LIB/setup-github-runner.sh" --label homelab-prod --name "$RUNNER_NAME" --token-stdin
fi
# config.sh copies LANG from the shell that ran it (here the laptop's, through ssh). The container
# has only C.UTF-8, and ansible-core 2.19 stops on a locale it does not have.
ct bash -c "cd $RUNNER_DIR && { test -f .service || ./svc.sh install runner; } && { grep -qx LANG=C.UTF-8 .env || { echo LANG=C.UTF-8 >.env && ./svc.sh stop >/dev/null; }; } && ./svc.sh start >/dev/null && chmod 600 .credentials .credentials_rsaparams"

echo "== checks"
rc=0
ct bash -s -- --check-inside <"$0" || rc=1
# A dropped probe times out (124); a refused one would mean nftables is not filtering.
probe=0; pve timeout 3 bash -c "exec 3<>/dev/tcp/${CT_IP}/22" 2>/dev/null || probe=$?
if [[ "$probe" == 124 ]]; then echo "ok   inbound TCP from the host is dropped"; else echo "FAIL inbound probe from the host: exit $probe (124 = dropped)"; rc=1; fi
state="$(gh api "repos/${REPO}/actions/runners" --jq ".runners[] | select(.name == \"$RUNNER_NAME\") | \"\(.status) \([.labels[].name] | join(\",\"))\"")"
if [[ "$state" == online*homelab-prod* ]]; then echo "ok   GitHub: $RUNNER_NAME $state"; else echo "FAIL GitHub: $RUNNER_NAME '${state:-not registered}'"; rc=1; fi
exit "$rc"
