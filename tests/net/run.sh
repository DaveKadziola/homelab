#!/usr/bin/env bash
# Net suite (F7-C / C3) — the network facts the homelab depends on.
#
#   dns/public          the zone from config/identities.yml resolves publicly
#   dns/host-resolver   the target host resolves names through its own resolver
#   dns/internal        the router/internal zone resolves from the target host
#   wireguard/*         a WireGuard peer has a recent handshake; wg gateway up
#   public/<name>       public_url in config/services.yml answers as expected
#   public/tls-expiry   the ACME certificate behind it is not about to expire
#   firewall/nas-*      allowed APP -> NAS NFS paths (2049/111)
#   firewall/denied-*   paths that must stay blocked
#
# Everything that needs the physical prod network SKIPs while prod is offline —
# an unreachable host is not evidence of a working (or broken) firewall.

set -uo pipefail

# shellcheck source=../lib/common.sh
source "$HL_REPO_ROOT/tests/lib/common.sh"

hl_env_load

DOMAIN="$(awk '/^domain:/ {print $2}' "$HL_REPO_ROOT/config/identities.yml")"
DOMAIN="${DOMAIN:-dkhomelabserver.xyz}"
NAS_IP="${HL_NAS_IP:-192.168.20.12}"
WG_GATEWAY="${HL_WG_GATEWAY:-10.10.10.1}"
# Proxmox web UI on the IOT VLAN: reachable from LAN/VPN, must not be reachable
# from the APP VLAN (only 2049/111 to the NAS is allowed — docs/network.md).
IOT_DENIED_HOST="${HL_IOT_DENIED_HOST:-192.168.20.20}"
IOT_DENIED_PORT="${HL_IOT_DENIED_PORT:-8006}"

# --------------------------------------------------------------------------
# DNS
# --------------------------------------------------------------------------
if ! command -v dig >/dev/null 2>&1; then
  report SKIP "dns/public" "dig (bind9-dnsutils) is not installed"
else
  answer="$(dig +short +time=3 +tries=1 A "grocery.${DOMAIN}" 2>/dev/null | tail -1)"
  if [[ -n "$answer" ]]; then
    report PASS "dns/public" "grocery.${DOMAIN} -> $answer"
  else
    report FAIL "dns/public" "grocery.${DOMAIN} does not resolve from this machine"
  fi
fi

if hl_host_up; then
  host_answer="$(hl_ssh "getent hosts grocery.${DOMAIN} 2>/dev/null | awk '{print \$1; exit}'")"
  if [[ -n "$host_answer" ]]; then
    report PASS "dns/host-resolver" "${HL_HOST} resolves grocery.${DOMAIN} -> $host_answer"
  else
    report FAIL "dns/host-resolver" "${HL_HOST} cannot resolve grocery.${DOMAIN} through its own resolver"
  fi

  internal_zone="$(awk '/dns_domain/ {gsub(/"/, "", $3); print $3; exit}' \
    "$HL_REPO_ROOT/terraform/environments/$HL_ENV/terraform.tfvars")"
  if [[ -z "$internal_zone" ]]; then
    report SKIP "dns/internal" "no node_config.dns_domain in terraform/environments/$HL_ENV/terraform.tfvars"
  else
    internal_answer="$(hl_ssh "getent hosts ${internal_zone} 2>/dev/null | awk '{print \$1; exit}'")"
    if [[ -n "$internal_answer" ]]; then
      report PASS "dns/internal" "${internal_zone} -> $internal_answer from ${HL_HOST}"
    else
      report SKIP "dns/internal" "internal zone '${internal_zone}' has no A record yet (no internal DNS server in $HL_ENV)"
    fi
  fi
else
  status="$(hl_unreachable_status)"
  report "$status" "dns/host-resolver" "host ${HL_HOST} unreachable"
  report "$status" "dns/internal" "host ${HL_HOST} unreachable"
fi

# --------------------------------------------------------------------------
# WireGuard (lives on OPNsense — checked from wherever this runs)
# --------------------------------------------------------------------------
if command -v wg >/dev/null 2>&1 && wg show interfaces >/dev/null 2>&1 &&
  [[ -n "$(wg show interfaces 2>/dev/null)" ]]; then
  latest="$(wg show all latest-handshakes 2>/dev/null | awk '{if ($3 > max) max = $3} END {print max + 0}')"
  now="$(date +%s)"
  if [[ "${latest:-0}" -gt 0 ]]; then
    age=$((now - latest))
    if [[ "$age" -lt 300 ]]; then
      report PASS "wireguard/handshake" "last peer handshake ${age}s ago on $(wg show interfaces)"
    else
      report FAIL "wireguard/handshake" "newest peer handshake is ${age}s old (>300s) on $(wg show interfaces)"
    fi
  else
    report FAIL "wireguard/handshake" "$(wg show interfaces) is up but no peer has ever completed a handshake"
  fi
else
  report SKIP "wireguard/handshake" "no WireGuard interface on this machine — wg0 lives on OPNsense (docs/wireguard.md)"
fi

if ping -c1 -W2 "$WG_GATEWAY" >/dev/null 2>&1; then
  report PASS "wireguard/gateway" "$WG_GATEWAY (wg0 on OPNsense) answers ICMP"
else
  report SKIP "wireguard/gateway" "$WG_GATEWAY not reachable — needs an active VPN session or the router online"
fi

# --------------------------------------------------------------------------
# public endpoints from config/services.yml (HAProxy + ACME on OPNsense)
# --------------------------------------------------------------------------
published=0
while IFS="$HL_FS" read -r name _priority _stack _container _check _port _path expect _profile _optional _extra public_url; do
  [[ -z "$public_url" ]] && continue
  published=1
  host="${public_url#*://}"
  host="${host%%/*}"
  port=443
  [[ "$public_url" == http://* ]] && port=80

  if ! hl_tcp "$host" "$port" 6; then
    report SKIP "public/$name" "$public_url — TCP $port not reachable (HAProxy on OPNsense / prod offline)"
    report SKIP "public/$name/tls-expiry" "$host:443 not reachable — cannot read the certificate"
    continue
  fi

  code="$(hl_http_code "$public_url")"
  if hl_in_list "$code" "${expect:-200}"; then
    report PASS "public/$name" "$public_url -> $code"
  else
    report FAIL "public/$name" "$public_url -> $code, expected ${expect:-200}"
  fi

  not_after="$(echo | timeout 10 openssl s_client -connect "${host}:443" -servername "$host" 2>/dev/null |
    openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)"
  if [[ -z "$not_after" ]]; then
    report FAIL "public/$name/tls-expiry" "could not read the TLS certificate of $host"
  else
    expiry_epoch="$(date -d "$not_after" +%s 2>/dev/null || echo 0)"
    days=$(((expiry_epoch - $(date +%s)) / 86400))
    if [[ "$expiry_epoch" -eq 0 ]]; then
      report FAIL "public/$name/tls-expiry" "cannot parse certificate notAfter '$not_after'"
    elif [[ "$days" -lt 14 ]]; then
      report FAIL "public/$name/tls-expiry" "$host certificate expires in ${days}d (ACME renewal is broken)"
    else
      report PASS "public/$name/tls-expiry" "$host certificate valid for ${days}d (until $not_after)"
    fi
  fi
done < <(hl_config services "$HL_ENV")

[[ "$published" -eq 0 ]] &&
  report SKIP "public/endpoints" "no service in config/services.yml declares a public_url"

# --------------------------------------------------------------------------
# cross-VLAN firewall paths (docs/network.md) — prod topology only
# --------------------------------------------------------------------------
if [[ "$HL_ENV" != "prod" ]]; then
  report SKIP "firewall/nas-nfs" "APP -> NAS 2049/111 only exists in prod (docs/network.md)"
  report SKIP "firewall/nas-portmap" "APP -> NAS 2049/111 only exists in prod (docs/network.md)"
  report SKIP "firewall/denied-iot" "APP -> IOT deny rule only exists in prod (docs/network.md)"
  report SKIP "firewall/dev-isolation" \
    "dev has no route to the prod VLANs and prod is offline — reachability proves nothing either way"
elif ! hl_host_up; then
  status="$(hl_unreachable_status)"
  report "$status" "firewall/nas-nfs" "prod host ${HL_HOST} unreachable"
  report "$status" "firewall/nas-portmap" "prod host ${HL_HOST} unreachable"
  report "$status" "firewall/denied-iot" "prod host ${HL_HOST} unreachable"
else
  # Allowed: APP -> NAS, NFS (2049) and portmapper (111).
  for entry in "nas-nfs:2049" "nas-portmap:111"; do
    ident="firewall/${entry%%:*}"
    nas_port="${entry##*:}"
    if hl_ssh "timeout 5 bash -c 'exec 3<>/dev/tcp/${NAS_IP}/${nas_port}'" 2>/dev/null; then
      report PASS "$ident" "APP ${HL_HOST} -> NAS ${NAS_IP}:${nas_port} open, as docs/network.md allows"
    else
      report FAIL "$ident" "APP ${HL_HOST} -> NAS ${NAS_IP}:${nas_port} blocked, but docs/network.md allows it"
    fi
  done

  # Denied: anything else from APP into IOT.
  if hl_ssh "timeout 5 bash -c 'exec 3<>/dev/tcp/${IOT_DENIED_HOST}/${IOT_DENIED_PORT}'" 2>/dev/null; then
    report FAIL "firewall/denied-iot" \
      "APP ${HL_HOST} reached IOT ${IOT_DENIED_HOST}:${IOT_DENIED_PORT} — only 2049/111 to ${NAS_IP} should pass"
  else
    report PASS "firewall/denied-iot" \
      "APP ${HL_HOST} cannot reach IOT ${IOT_DENIED_HOST}:${IOT_DENIED_PORT}, as intended"
  fi
fi

exit 0
