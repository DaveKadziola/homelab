# Backup

**Status:** F5 jobs exist on three hosts: the apps guest (databases, volumes, repo, offsite), the NAS (Home Assistant, OPNsense, freshness check) and Proxmox (VM dumps). DEV uses loopback NFS on `ubuntu-apps-dev`, which is NAS and apps host at once, and the HAOS twin.

## Layout

Declared in [`config/storage.yml`](../config/storage.yml). Two directories:

- the shared one: on the NAS `<export_root>/backups` (prod: `/srv/purple/backups` on Purple, bind-mounted to `/export/backups`), on the apps guest the NFS mount `backup_root` (`/mnt/homelab/backups`), in the read-only Samba share `backups`, and the source of offsite;
- the NAS-private one, `nas_private_root` (prod `/srv/purple/nas-backups`, DEV `/srv/homelab-nas-backups`): router config, HA UI YAML and VM dumps, which hold password hashes and keys. Outside the export tree, so the apps host (root over NFS) and the writable Samba shares do not reach it; only the Proxmox host mounts its `vzdump` folder. The owner reads it, next to the shared streams, through the read-only Samba share `all-backups` (both trees bound read-only below `/srv/backups-all`), open only to `samba.admin_hosts` (prod: the laptop `192.168.1.100`; DEV: `192.168.122.1`), since 2026-10-23. It is not copied offsite.

| Stream | Runs on, by | DEV | Prod |
|--------|-------------|-----|------|
| Postgres (shared + Immich) | apps, `pg-dump.sh` (`homelab-backup.timer` 03:15) | runs | runs |
| App volumes (not media libraries) | apps, `volumes.sh` | runs | runs |
| Deployed `/opt/homelab` zip | apps, `repo-zip.sh` | runs | runs |
| rclone → `pcloud-crypt:homelab-backups` (only `offsite.include`: postgres, volumes, homeassistant, repo-zip) | apps, `rclone-offsite.sh`; writes `.offsite-ok` | disabled | needs `RCLONE_CONFIG` with a **crypt** remote, else it skips |
| Home Assistant full backup (`ha-full-*.tar`, `HA_BACKUP_PASSWORD`) | NAS, `ha-pull.sh` -> `utils/ha.py backup` (`homelab-nas-backup.timer` 02:30) | HAOS twin | needs `HA_TOKEN` |
| Home Assistant UI YAML snapshots (keep 30, only on change), NAS-private | NAS, `ha-yaml.sh` -> `utils/ha.py export-ui` | HAOS twin | needs `HA_TOKEN`, `HA_SSH_PRIV` |
| OPNsense `config.xml`, NAS-private | NAS, `opnsense.sh`, key with a forced command | SKIP (prod only) | one file 2026-10-22 (`config-20261022T131513Z.xml`, mode 600); timer 02:30 |
| VM dumps 101/102 (`vzdump/dump/`), NAS-private | Proxmox job `homelab-vms` 04:30 onto storage `nas-backups` (NFS `<nas_private_root>/vzdump`, only to the PVE host), `utils/pve-backup-job.py` | job created, disabled | runs |
| Freshness of every stream | NAS, `check-fresh.py` (`homelab-backup-check.timer` 06:00) -> Uptime Kuma push | runs | runs |

Retention **A15 = 2 newest** artefacts **per name prefix** (`linkwarden-*.sql.gz`, not “2 files in the whole folder”). `hl_prune` in `utils/backup/lib.sh`; Home Assistant: `ha.py backup --keep 2`; VM dumps: `prune-backups keep-last=2` on the Proxmox job. Max ages and the Kuma push monitors: [`config/monitoring.yml`](../config/monitoring.yml) `backups`.

Offsite copies only the streams in `offsite.include` and only to an rclone **crypt** remote (`rclone-offsite.sh` skips a plain one: dumps and volume tars hold app data and credentials). It keeps every upload (`rclone copy`): remote retention is the owner's decision. The crypt remote `pcloud-crypt` (`remote = pcloud:homelab-crypt`, names encrypted) was added on 2026-10-21; its passwords live only in `RCLONE_CONFIG` (GH env prod, Bitwarden `homelab/RCLONE_CONFIG/prod`) - without them the offsite copy cannot be read. rclone comes from the pinned upstream release (`deploy-storage.yml`, 1.75.2), not apt. Some rclone requests to pCloud get no answer (2026-10-21: ~40 % of calls with 1.60.1 and 1.75.2, HTTP/2 or 1.1; the same API calls from Python never stalled), so `rclone-offsite.sh` runs with a 60 s idle timeout, retries and a 6 h limit. A delete right after an upload can answer "not found" (pCloud lag); `copy` does not delete. Offsite is **DR only** — not Immich / Jellyfin / Navidrome libraries (those already live on pCloud separately). Media on prod is the NFS share on SA500, not a second copy in this job. A homelab backup of the media to pCloud is deferred until prod runs; the owner will adjust the pCloud targets ([decision 0002](decisions/0002-nas-layout-and-samba.md)).

The Samba share `share` (`/srv/purple/share`) is **not backed up**: it is outside the NFS tree, so neither the timer nor offsite sees it.

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

Timers: apps `homelab-backup.timer` **03:15** (`journalctl -u homelab-backup`); NAS `homelab-nas-backup.timer` **02:30** and `homelab-backup-check.timer` **06:00** (`journalctl -u homelab-nas-backup -u homelab-backup-check`); Proxmox job `homelab-vms` **04:30** (Datacenter -> Backup). The NAS jobs live in `/opt/homelab-nas` (own tree: on DEV the same guest also carries `/opt/homelab`).

```bash
# Run the NAS streams now / see every stream's age without pushing (on the NAS, as root)
sudo env HOMELAB_ENV=prod HOMELAB_CONFIG_DIR=/opt/homelab-nas/config HOMELAB_SECRETS_DIR=/opt/homelab-nas/secrets \
  HL_REPO_ROOT=/opt/homelab-nas /opt/homelab-nas/utils/backup/run-nas.sh --env prod
sudo env HOMELAB_CONFIG_DIR=/opt/homelab-nas/config python3 /opt/homelab-nas/utils/backup/check-fresh.py --env prod --dry-run
```

Restore one gzip SQL dump:

```bash
./utils/backup/restore-pg.sh --env dev --db scratch --file /mnt/homelab/backups/postgres/linkwarden-….sql.gz --create
```

Over an existing database: `--replace` (drop + create), with `--owner ROLE` when the app owns its tables, and `--container/--user/--password-secret` for Immich's own Postgres. Stop the app first. Per-database commands: `rebuild.md` step 7.

## What is still not automatic

- Attaching SA500/Purple (`utils/pve-attach-nas-disks.sh --env prod`) and their one-time format (`nas_wipe`, [`storage.md`](storage.md#attach-and-format-run-order))
- Interactive rclone OAuth → `rclone config create pcloud pcloud` then `utils/setup-rclone-pcloud.sh --push-gh` (see [`security.md`](security.md))
- A long-lived `HA_TOKEN` on the T620 (owner, HA profile)
- The router side of the OPNsense stream was installed 2026-10-22 (`utils/opnsense-backup-key.sh`). Revert that config from `/conf/config.xml.homelab-v2-20261022-151335` with `configctl auth sync user root`.

## Related

- [`storage.md`](storage.md) · [`dr.md`](dr.md) · [`rebuild.md`](rebuild.md) · [`docs/f5-storage.md`](../docs/f5-storage.md)
