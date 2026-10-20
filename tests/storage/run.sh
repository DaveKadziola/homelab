#!/usr/bin/env bash
# Storage suite (F5) — NAS disks, what NFS really shows, and Samba (config/storage.yml).
#
#   disk/<label>@<path>   a passthrough filesystem or bind is mounted on the NAS with its LABEL
#   nfs/marker-<label>    the apps host sees that filesystem through NFS (crossmnt), not the
#                         empty root-disk directory under the mount point
#   nfs/guard             nfs-server requires every passthrough mount (missing disk -> NFS down)
#   samba/smbd            smbd is running
#   samba/hosts-allow     smb.conf allows exactly the clients in config/storage.yml
#   samba/login           the admin login lists the share, media and backups shares (from the NAS
#                         itself: the CI runner is not an allowed client)
#   samba/backups-ro      a write to the backups share is refused
#   backup/fresh-<stream> the newest artefact of each stream in config/monitoring.yml is younger
#                         than its max age, as check-fresh.py on the NAS sees it (dry run, no
#                         push); a stream that never produced a file is SKIP (prerequisite missing
#                         or first night)
#
# Read-only: listings and stat calls; the only write is the backups probe, which must be refused
# (if it ever succeeds, the probe file is deleted again and the check fails).

set -uo pipefail

# shellcheck source=../lib/common.sh
source "$HL_REPO_ROOT/tests/lib/common.sh"

hl_env_load

mounts=()
markers=()
while IFS= read -r line; do
  case "$line" in
    MOUNT=*) mounts+=("${line#MOUNT=}") ;;
    MARKER=*) markers+=("${line#MARKER=}") ;;
    ?*) export "${line?}" ;;
  esac
done < <(hl_config storage "$HL_ENV")

# On DEV the NAS is the apps guest itself; on prod it is ubuntu-nas.
hl_nas_ssh() {
  if [[ "$HL_NAS_HOST" == "$HL_HOST" ]]; then
    hl_ssh "$@"
    return
  fi
  local opts=(
    -o BatchMode=yes -o ConnectTimeout="$HL_SSH_TIMEOUT" -o StrictHostKeyChecking=accept-new
    -o LogLevel=ERROR -o ControlMaster=auto -o ControlPath="$HL_TMP/ssh-%C" -o ControlPersist=120
  )
  [[ -n "${HL_NAS_KEY:-}" ]] && opts+=(-i "$HL_NAS_KEY")
  ssh "${opts[@]}" "${HL_NAS_USER}@${HL_NAS_HOST}" "$@"
}

if ! hl_nas_ssh true >/dev/null 2>&1; then
  report "$(hl_unreachable_status)" "nas/reachable" "cannot ssh to ${HL_NAS_USER}@${HL_NAS_HOST}"
  exit 0
fi

# --------------------------------------------------------------------------
# Passthrough disks and NFS visibility
# --------------------------------------------------------------------------
if [[ "${HL_NAS_PASSTHROUGH:-0}" == "0" ]]; then
  for id in disk/all nfs/markers nfs/guard; do
    report SKIP "$id" "config/storage.yml environments.${HL_ENV}.passthrough is empty - no SA500/Purple here"
  done
else
  for row in "${mounts[@]}"; do
    path="${row%%|*}" label="${row##*|}"
    got="$(hl_nas_ssh "findmnt -n -o LABEL --mountpoint '$path'" 2>/dev/null | head -1)"
    if [[ "$got" == "$label" ]]; then
      report PASS "disk/${label}@${path}" "mounted, LABEL=${label}"
    else
      report FAIL "disk/${label}@${path}" "not mounted with LABEL=${label} (findmnt: '${got:-nothing}')"
    fi
  done

  if hl_host_up; then
    for row in "${markers[@]}"; do
      path="${row%%|*}" label="${row##*|}"
      if hl_ssh "test -f '$path'" 2>/dev/null; then
        report PASS "nfs/marker-${label}" "$path visible through NFS"
      else
        report FAIL "nfs/marker-${label}" "$path missing: NFS shows the root-disk directory (mount or crossmnt)"
      fi
    done
  else
    report "$(hl_unreachable_status)" "nfs/markers" "apps host ${HL_HOST} unreachable"
  fi

  required="$(hl_nas_ssh "systemctl show nfs-server -p RequiresMountsFor --value" 2>/dev/null)"
  missing=()
  for row in "${mounts[@]}"; do
    path="${row%%|*}"
    [[ " $required " == *" $path "* ]] || missing+=("$path")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    report PASS "nfs/guard" "nfs-server requires ${required}"
  else
    report FAIL "nfs/guard" "nfs-server does not require ${missing[*]} (drop-in homelab-mounts.conf)"
  fi
fi

# --------------------------------------------------------------------------
# Backup freshness (utils/backup/check-fresh.py on the NAS, no push)
# --------------------------------------------------------------------------
fresh="$(hl_nas_ssh "sudo -n env HOMELAB_CONFIG_DIR=/opt/homelab-nas/config python3 /opt/homelab-nas/utils/backup/check-fresh.py --env $HL_ENV --dry-run" 2>/dev/null)"
if [[ -z "$fresh" ]]; then
  report SKIP "backup/fresh" "check-fresh.py is not on the NAS yet (deploy-storage.yml)"
else
  while read -r verdict stream rest; do
    [[ -z "$stream" ]] && continue
    if [[ "$verdict" == "ok" ]]; then
      report PASS "backup/fresh-$stream" "$rest"
    elif [[ "$rest" == "no file matches"* ]]; then
      report SKIP "backup/fresh-$stream" "$rest"
    else
      report FAIL "backup/fresh-$stream" "$rest"
    fi
  done <<<"$fresh"
fi

# --------------------------------------------------------------------------
# Samba
# --------------------------------------------------------------------------
if [[ -z "${HL_SMB_LOGIN:-}" ]]; then
  report SKIP "samba/all" "no samba block for ${HL_ENV} in config/storage.yml"
  exit 0
fi

if [[ "$(hl_nas_ssh "systemctl is-active smbd" 2>/dev/null)" == "active" ]]; then
  report PASS "samba/smbd" "smbd active on ${HL_NAS_HOST}"
else
  report FAIL "samba/smbd" "smbd is not active on ${HL_NAS_HOST}"
fi

norm() { tr ', ' '\n\n' | sed '/^$/d' | sort | paste -sd' ' -; }
want="$(printf '%s' "$HL_SMB_ALLOW" | norm)"
got="$(hl_nas_ssh "testparm -s --parameter-name='hosts allow' 2>/dev/null" | norm)"
if [[ "$got" == "$want" ]]; then
  report PASS "samba/hosts-allow" "$got"
else
  report FAIL "samba/hosts-allow" "smb.conf allows '${got}', config/storage.yml says '${want}'"
fi

# Password from the environment (CI) or the operator cache; it reaches the NAS on stdin.
password="${!HL_SMB_SECRET:-}"
cache="${HOMELAB_SECRETS_DIR:-$HOME/.homelab-secrets}/${HL_ENV}/${HL_SMB_SECRET}"
[[ -z "$password" && -r "$cache" ]] && password="$(cat "$cache")"
if [[ -z "$password" ]]; then
  report SKIP "samba/login" "${HL_SMB_SECRET} is not in the environment or ${cache}"
else
  listing="$(printf '%s' "$password" | hl_nas_ssh \
    "PASSWD=\"\$(cat)\" smbclient -g -m SMB3 -L //127.0.0.1 -U '${HL_SMB_LOGIN}' 2>/dev/null")"
  if grep -q '^Disk|share|' <<<"$listing" && grep -q '^Disk|media|' <<<"$listing" \
     && grep -q '^Disk|backups|' <<<"$listing"; then
    report PASS "samba/login" "${HL_SMB_LOGIN} lists share, media and backups"
  else
    report FAIL "samba/login" "${HL_SMB_LOGIN} cannot list share, media and backups on //${HL_NAS_HOST}"
  fi

  probe="$(printf '%s' "$password" | hl_nas_ssh \
    "PASSWD=\"\$(cat)\" smbclient -m SMB3 //127.0.0.1/backups -U '${HL_SMB_LOGIN}' -c 'put /etc/hostname .rw-probe' 2>&1")"
  if grep -q -E 'NT_STATUS_(ACCESS_DENIED|MEDIA_WRITE_PROTECTED)' <<<"$probe"; then
    report PASS "samba/backups-ro" "write to backups refused ($(grep -o -E 'NT_STATUS_[A-Z_]+' <<<"$probe" | head -1))"
  else
    printf '%s' "$password" | hl_nas_ssh \
      "PASSWD=\"\$(cat)\" smbclient -m SMB3 //127.0.0.1/backups -U '${HL_SMB_LOGIN}' -c 'del .rw-probe'" >/dev/null 2>&1
    report FAIL "samba/backups-ro" "the backups share accepted a write"
  fi
  unset password
fi
