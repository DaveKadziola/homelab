# Backup

**Status:** F5 jobs exist. DEV uses loopback NFS on `ubuntu-apps-dev`. Prod Purple / rclone / vzdump / HA are coded and **SKIP** until those hosts exist.

## Layout

Declared in [`config/storage.yml`](../../config/storage.yml). The timer always writes to `backup_root` on the **apps** guest (`/mnt/homelab/backups`), which is the NFS mount of the NAS export.

| Stream | Script | DEV | Prod |
|--------|--------|-----|------|
| Postgres (shared + Immich) | `utils/backup/pg-dump.sh` | runs | runs |
| App volumes (not media libraries) | `utils/backup/volumes.sh` | runs | runs |
| Deployed `/opt/homelab` zip | `utils/backup/repo-zip.sh` | runs | runs |
| OPNsense `config.xml` | `utils/backup/opnsense.sh` | SKIP (no `.20.1`) | when the router answers |
| Home Assistant Supervisor `.tar` | `utils/backup/ha-pull.sh` | SKIP (no T620) | when `HA_TOKEN` + `.20.13` |
| vzdump | `utils/backup/vzdump.sh` | SKIP (not on PVE) | run on the physical host |
| rclone → `pcloud:homelab-backups` | `utils/backup/rclone-offsite.sh` | disabled | needs `RCLONE_CONFIG` |

Retention **A15 = 2 newest** artefacts **per name prefix** (`linkwarden-*.sql.gz`, not “2 files in the whole folder”). `hl_prune` in `utils/backup/lib.sh`.

Offsite is **DR only** — not Immich / Jellyfin / Navidrome libraries (those already live on pCloud separately). Media on prod is the NFS share on SA500, not a second copy in this job.

## Operator

```bash
# Deploy exports + timer (DEV = loopback NFS on the same guest)
export HOMELAB_ENV=dev
ansible-playbook -i ansible/environments/dev/hosts.ini ansible/playbooks/deploy-storage.yml

# Run now (on the apps guest, as root)
sudo env HOMELAB_ENV=dev HOMELAB_CONFIG_DIR=/opt/homelab/config \
  HOMELAB_SECRETS_DIR=/opt/homelab/secrets \
  /opt/homelab/utils/backup/run-all.sh --env dev

# Prove a dump can come back (throwaway DB only; not in --suite all)
./utils/run-tests.sh --env dev --suite restore
```

Timer: `homelab-backup.timer` at **03:15**. `journalctl -u homelab-backup`.

Restore one gzip SQL dump:

```bash
./utils/backup/restore-pg.sh --env dev --db scratch --file /mnt/homelab/backups/postgres/linkwarden-….sql.gz --create
```

Do not restore over a live app database without stopping that app.

## What is still not automatic

- Filling `passthrough[].by_id` and `utils/pve-attach-nas-disks.sh --env prod`
- Interactive rclone OAuth → `rclone config create pcloud pcloud` then `utils/setup-rclone-pcloud.sh --push-gh` (see [`security.md`](security.md))
- Flashing HAOS on the T620 and a long-lived `HA_TOKEN`
- Running `vzdump` on physical PVE (the script no-ops on the apps VM)

## Related

- [`storage.md`](storage.md) · [`dr.md`](dr.md) · [`rebuild.md`](rebuild.md) · [`docs/f5-storage.md`](../f5-storage.md)
