#!/usr/bin/env bash
# Restore suite (F5 / C4) — prove backup jobs exist and a scratch DB round-trips.
#
# Not part of --suite all (monthly / after a backup change). Safe: the only
# write is a throwaway database `f5_restore_scratch`, dropped at the end.
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$HL_REPO_ROOT/tests/lib/common.sh"

hl_env_load

if ! hl_host_up; then
  status="$(hl_unreachable_status)"
  report "$status" "host/ssh" "cannot ssh to ${HL_SSH_USER}@${HL_HOST} (env $HL_ENV)"
  exit 0
fi
report PASS "host/ssh" "ssh ${HL_SSH_USER}@${HL_HOST} ok"

# --------------------------------------------------------------------------
# NFS mount + timer
# --------------------------------------------------------------------------
if hl_ssh "findmnt -n -T /mnt/homelab 2>/dev/null | grep -q nfs"; then
  report PASS "storage/nfs" "/mnt/homelab is an NFS mount"
else
  report FAIL "storage/nfs" "/mnt/homelab is not mounted as nfs (deploy-storage.yml?)"
fi

if hl_ssh "test -d /mnt/homelab/backups"; then
  report PASS "storage/backups-dir" "/mnt/homelab/backups exists"
else
  report FAIL "storage/backups-dir" "/mnt/homelab/backups missing"
fi

if hl_ssh "systemctl is-enabled homelab-backup.timer >/dev/null 2>&1"; then
  when="$(hl_ssh "systemctl show -p NextElapseUSecRealtime --value homelab-backup.timer" 2>/dev/null || true)"
  report PASS "backup/timer" "homelab-backup.timer enabled${when:+ next=$when}"
else
  report FAIL "backup/timer" "homelab-backup.timer is not enabled"
fi

if hl_ssh "test -x /opt/homelab/utils/backup/run-all.sh"; then
  report PASS "backup/scripts" "run-all.sh is on the host"
else
  report FAIL "backup/scripts" "/opt/homelab/utils/backup/run-all.sh missing"
fi

# --------------------------------------------------------------------------
# Retention helper (keep=2)
# --------------------------------------------------------------------------
if hl_ssh "sudo -n env HOMELAB_ENV=$HL_ENV HOMELAB_CONFIG_DIR=/opt/homelab/config /opt/homelab/utils/backup/check-prune.sh"; then
  report PASS "backup/retention" "hl_prune keeps 2 newest artefacts"
else
  report FAIL "backup/retention" "check-prune.sh failed"
fi

# --------------------------------------------------------------------------
# Run the nightly job once (rclone/HA/vzdump/OPNsense skip on DEV)
# --------------------------------------------------------------------------
if hl_ssh "sudo -n env HOMELAB_ENV=$HL_ENV HOMELAB_CONFIG_DIR=/opt/homelab/config HOMELAB_SECRETS_DIR=/opt/homelab/secrets HL_REPO_ROOT=/opt/homelab /opt/homelab/utils/backup/run-all.sh --env $HL_ENV"; then
  report PASS "backup/run-all" "run-all.sh exited 0"
else
  report FAIL "backup/run-all" "run-all.sh failed — see journalctl -u homelab-backup"
fi

pg_n="$(hl_ssh "ls -1 /mnt/homelab/backups/postgres/*.sql.gz 2>/dev/null | wc -l")"
pg_n="${pg_n// /}"
if [[ "${pg_n:-0}" -ge 6 ]]; then
  report PASS "backup/postgres-artefacts" "${pg_n} pg_dump file(s) (one per database, keep=2 per name)"
else
  report FAIL "backup/postgres-artefacts" "expected several per-DB dumps, found ${pg_n:-0}"
fi

if hl_ssh "ls /mnt/homelab/backups/volumes/*.tar.gz >/dev/null 2>&1"; then
  n="$(hl_ssh "ls -1 /mnt/homelab/backups/volumes/*.tar.gz 2>/dev/null | wc -l")"
  report PASS "backup/volume-artefacts" "${n} volume tar(s)"
else
  report FAIL "backup/volume-artefacts" "no volume tars (are the named volumes present?)"
fi

# Streams that cannot run here must SKIP with a reason, not pretend to PASS.
if [[ "$HL_ENV" == "dev" ]]; then
  report SKIP "backup/rclone" "storage.yml environments.dev.rclone is false"
  report SKIP "backup/homeassistant" "no ha_host on DEV; T620 is not flashed from this repo"
  report SKIP "backup/vzdump" "vzdump is not on the apps guest (physical PVE only)"
  report SKIP "backup/opnsense" "192.168.20.1 is not on the libvirt network"
fi

# --------------------------------------------------------------------------
# Scratch dump → restore (does not touch app DBs)
# --------------------------------------------------------------------------
if hl_ssh "sudo -n env HOMELAB_ENV=$HL_ENV HOMELAB_CONFIG_DIR=/opt/homelab/config HOMELAB_SECRETS_DIR=/opt/homelab/secrets /opt/homelab/utils/backup/restore-scratch.sh"; then
  report PASS "postgres/scratch-roundtrip" "f5_restore_scratch dumped and restored"
else
  report FAIL "postgres/scratch-roundtrip" "restore-scratch.sh failed"
fi
