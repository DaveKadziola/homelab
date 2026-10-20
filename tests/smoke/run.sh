#!/usr/bin/env bash
# Smoke suite (F7-C / C1) — is every service in config/services.yml actually serving?
#
# Per service, driven only by config/services.yml:
#   <name>/container   container exists, is running and is not restarting
#   <name>/stability   no restart loop, not OOM-killed
#   <name>/port        the declared host port is published by Docker
#   <name>/endpoint    HTTP(S) status is one of `expect`, or the TCP port accepts
#
# With compose profile proxy (decision 0007), per app name of utils/gen-proxy-config.py, resolved to the
# host with curl --resolve (no DNS needed):
#   proxy/http-redirect      http://<name>/ answers a redirect to https
#   proxy/<name>             without a session: a redirect to https://auth.<domain>/ ; with
#                            `auth_bypass: all`: the app itself (no redirect to Authelia)
#   proxy/<name>-api         an `auth_bypass` path answers without a redirect to Authelia
#   proxy/login              Authelia login (AUTHELIA_ADMIN_PASSWORD), then omni-tools.<domain> (no own
#                            login) answers 200
#
# `optional: true` and a compose `profile` that is not enabled turn a missing
# service into SKIP instead of FAIL. Nothing here writes to the host.

set -uo pipefail

# shellcheck source=../lib/common.sh
source "$HL_REPO_ROOT/tests/lib/common.sh"

hl_env_load

SERVICES="$HL_TMP/services.tsv"
DOCKER_FACTS="$HL_TMP/docker-facts.txt"
hl_config services "$HL_ENV" >"$SERVICES"

# --------------------------------------------------------------------------
# host + docker facts (one SSH round trip for everything)
# --------------------------------------------------------------------------
if ! hl_host_up; then
  status="$(hl_unreachable_status)"
  report "$status" "host/ssh" "cannot ssh to ${HL_SSH_USER}@${HL_HOST} (env $HL_ENV)"
  while IFS="$HL_FS" read -r name _rest; do
    [[ -z "$name" ]] && continue
    report SKIP "$name/container" "host ${HL_HOST} unreachable"
  done <"$SERVICES"
  exit 0
fi
report PASS "host/ssh" "ssh ${HL_SSH_USER}@${HL_HOST} ok"

DOCKER_FMT='{{.Name}}|{{.State.Status}}|{{.State.Restarting}}|{{.RestartCount}}|{{.State.OOMKilled}}|{{.HostConfig.NetworkMode}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}|{{range $p, $c := .NetworkSettings.Ports}}{{range $c}}{{.HostPort}},{{end}}{{end}}'
if ! hl_ssh "docker ps -aq | xargs -r docker inspect --format '$DOCKER_FMT'" \
  >"$DOCKER_FACTS" 2>/dev/null; then
  report FAIL "host/docker" "'docker inspect' failed on ${HL_HOST} (is the user in the docker group?)"
  exit 0
fi
report PASS "host/docker" "$(wc -l <"$DOCKER_FACTS") container(s) inspected"

# Enabled compose profiles decide whether a profiled service must be up.
ENABLED_PROFILES="$(hl_ssh 'grep -h "^COMPOSE_PROFILES=" /opt/homelab/compose/core/.env 2>/dev/null | tail -1 | cut -d= -f2-' 2>/dev/null || true)"
if [[ -z "$ENABLED_PROFILES" ]]; then
  # Same defaults as deploy-core.yml: config/services.yml environments.<env>.profiles.
  ENABLED_PROFILES="${HL_COMPOSE_PROFILES:-$HL_PROFILES}"
  hl_note "  (COMPOSE_PROFILES not readable on host, assuming '$ENABLED_PROFILES')"
fi

# docker_fact <container> -> the inspect line, or empty
docker_fact() {
  awk -F'|' -v want="/$1" '$1 == want { print; exit }' "$DOCKER_FACTS"
}

# --------------------------------------------------------------------------
# per service
# --------------------------------------------------------------------------
while IFS="$HL_FS" read -r name priority stack container check port path expect profile optional extra_ports public_url; do
  [[ -z "$name" ]] && continue

  fact="$(docker_fact "$container")"
  IFS='|' read -r _cname state restarting restarts oomkilled netmode health published <<<"${fact:-|||||||}"
  # Docker lists every binding twice (IPv4 + IPv6); one entry per port reads better.
  published="$(tr ',' '\n' <<<"${published%,}" | grep -v '^$' | sort -un | paste -sd, -)"

  # ---- container ----
  if [[ -z "$fact" ]]; then
    reason="container '$container' does not exist on ${HL_HOST}"
    if [[ -n "$profile" ]] && ! hl_in_list "$profile" "$ENABLED_PROFILES"; then
      report SKIP "$name/container" "compose profile '$profile' not enabled (COMPOSE_PROFILES=$ENABLED_PROFILES)"
      continue
    fi
    if [[ "$optional" == "true" ]]; then
      report SKIP "$name/container" "optional service — $reason"
      continue
    fi
    report FAIL "$name/container" "$reason"
    continue
  fi

  if [[ "$state" == "running" && "$restarting" == "false" ]]; then
    detail="Up"
    [[ "$health" != "-" ]] && detail="Up (health: $health)"
    report PASS "$name/container" "$detail"
  elif [[ "$optional" == "true" ]]; then
    report SKIP "$name/container" "optional service — state '$state' (restarting=$restarting)"
    continue
  else
    report FAIL "$name/container" "state '$state' (restarting=$restarting, restarts=$restarts)"
    continue
  fi

  # ---- stability: restart loop / OOM ----
  if [[ "$oomkilled" == "true" && "$state" == "running" ]]; then
    report FAIL "$name/stability" "a process inside was OOM-killed at the cgroup limit (container still Up, restarts=$restarts) — raise mem_limit in compose"
  elif [[ "$oomkilled" == "true" ]]; then
    report FAIL "$name/stability" "last exit was an OOM kill (restarts=$restarts) — raise mem_limit in compose"
  elif [[ "${restarts:-0}" -gt "$HL_RESTART_LIMIT" ]]; then
    report FAIL "$name/stability" "restart loop: RestartCount=$restarts (limit $HL_RESTART_LIMIT)"
  else
    report PASS "$name/stability" "RestartCount=$restarts, no OOM kill"
  fi

  # ---- published port ----
  if [[ "$check" == "container" ]]; then
    report SKIP "$name/port" "check=container — no host port expected (declared port is internal)"
  elif [[ -z "$port" ]]; then
    report SKIP "$name/port" "no port declared in config/services.yml"
  elif [[ "$netmode" == "host" ]]; then
    report SKIP "$name/port" "network_mode=host — Docker publishes nothing"
  else
    missing=()
    for want in $port ${extra_ports//,/ }; do
      hl_in_list "$want" "$published" || missing+=("$want")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
      report PASS "$name/port" "published on the host: $published"
    else
      report FAIL "$name/port" "port(s) ${missing[*]} not published (published: ${published:-none})"
    fi
  fi

  # ---- endpoint ----
  case "$check" in
    http | https)
      url="${check}://${HL_HOST}:${port}${path:-/}"
      code="$(hl_http_code "$url")"
      if [[ "$code" == "000" ]]; then
        report FAIL "$name/endpoint" "$url did not answer within ${HL_HTTP_TIMEOUT}s"
      elif hl_in_list "$code" "${expect:-200}"; then
        report PASS "$name/endpoint" "$url -> $code"
      else
        report FAIL "$name/endpoint" "$url -> $code, expected ${expect:-200}"
      fi
      ;;
    tcp)
      if hl_tcp "$HL_HOST" "$port"; then
        report PASS "$name/endpoint" "tcp ${HL_HOST}:${port} accepts connections"
      else
        report FAIL "$name/endpoint" "tcp ${HL_HOST}:${port} refused"
      fi
      ;;
    container)
      report SKIP "$name/endpoint" "check=container — no listener to probe"
      ;;
    *)
      report FAIL "$name/endpoint" "unknown check type '$check' in config/services.yml"
      ;;
  esac
done <"$SERVICES"

# --------------------------------------------------------------------------
# app names through Caddy + Authelia (profile proxy)
# --------------------------------------------------------------------------
if [[ ",$ENABLED_PROFILES," != *",proxy,"* ]]; then
  report SKIP "proxy/all" "compose profile proxy is not enabled for $HL_ENV"
  exit 0
fi
auth="auth.${HL_DOMAIN}"
# -k: DEV serves Caddy's internal CA. Prints "<code> <redirect location>".
probe() {
  local name="$1" path="${2:-/}" scheme="${3:-https}" port=443
  [[ "$scheme" == http ]] && port=80
  curl -sk -o /dev/null --max-time "$HL_HTTP_TIMEOUT" --resolve "${name}:${port}:${HL_HOST}" \
    -w '%{http_code} %{redirect_url}' "${@:4}" "${scheme}://${name}${path}"
}
first="$(python3 "$HL_REPO_ROOT/utils/gen-proxy-config.py" --env "$HL_ENV" --file list --profiles "$ENABLED_PROFILES" | head -1 | cut -f1)"
read -r code loc <<<"$(probe "$first" / http)"
if [[ "$code" =~ ^30[178]$ && "$loc" == https://* ]]; then
  report PASS "proxy/http-redirect" "http://$first -> $code $loc"
else
  report FAIL "proxy/http-redirect" "http://$first -> ${code:-none} ${loc:-}"
fi
while IFS=$'\t' read -r name bypass; do
  [[ -z "$name" ]] && continue
  short="${name%%.*}"
  read -r code loc <<<"$(probe "$name" /)"
  if [[ "$bypass" == all ]]; then
    if [[ "$code" != 000 && "$loc" != https://${auth}/* ]]; then
      report PASS "proxy/$short" "$name -> $code without Authelia (auth_bypass: all)"
    else
      report FAIL "proxy/$short" "$name -> ${code} ${loc} (expected the app itself)"
    fi
  elif [[ "$code" == 302 && "$loc" == https://${auth}/* ]]; then
    report PASS "proxy/$short" "$name -> Authelia login"
  else
    report FAIL "proxy/$short" "$name -> ${code} ${loc:-} (expected 302 to https://${auth}/)"
  fi
  if [[ -n "$bypass" && "$bypass" != all ]]; then
    # First regex of the list, turned into a path: ^/api([/?].*)?$ -> /api
    api="$(sed -E 's/,.*//; s/^\^//; s/\(.*$//; s/\$$//' <<<"$bypass")"
    read -r code loc <<<"$(probe "$name" "$api")"
    if [[ "$code" != 000 && "$loc" != https://${auth}/* ]]; then
      report PASS "proxy/$short-api" "$name$api -> $code without Authelia"
    else
      report FAIL "proxy/$short-api" "$name$api -> ${code} ${loc} (auth_bypass not applied)"
    fi
  fi
done < <(python3 "$HL_REPO_ROOT/utils/gen-proxy-config.py" --env "$HL_ENV" --file list --profiles "$ENABLED_PROFILES")

password="${AUTHELIA_ADMIN_PASSWORD:-}"
cache="${HOMELAB_SECRETS_DIR:-$HOME/.homelab-secrets}/${HL_ENV}/AUTHELIA_ADMIN_PASSWORD"
[[ -z "$password" && -r "$cache" ]] && password="$(cat "$cache")"
if [[ -z "$password" ]]; then
  report SKIP "proxy/login" "AUTHELIA_ADMIN_PASSWORD is not in the environment or ${cache}"
else
  jar="$HL_TMP/authelia.jar"
  body="$(python3 -c 'import json,sys; print(json.dumps({"username": "admin", "password": sys.stdin.read().rstrip("\n"), "keepMeLoggedIn": False}))' <<<"$password")"
  unset password
  login="$(printf '%s' "$body" | curl -sk -o /dev/null --max-time "$HL_HTTP_TIMEOUT" --resolve "${auth}:443:${HL_HOST}" \
    -c "$jar" -H 'Content-Type: application/json' --data @- -w '%{http_code}' "https://${auth}/api/firstfactor")"
  read -r code loc <<<"$(probe "omni-tools.${HL_DOMAIN}" / https -b "$jar")"
  if [[ "$login" == 200 && "$code" == 200 ]]; then
    report PASS "proxy/login" "Authelia login, then omni-tools.${HL_DOMAIN} -> 200"
  else
    report FAIL "proxy/login" "login -> ${login:-none}, omni-tools.${HL_DOMAIN} -> ${code:-none} ${loc:-}"
  fi
fi

exit 0
