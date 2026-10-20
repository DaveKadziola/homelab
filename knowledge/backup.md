# Backup

**Status:** F5 jobs exist on three hosts: the apps guest (databases, volumes, repo, offsite), the NAS (Home Assistant, OPNsense, freshness check) and Proxmox (VM dumps). DEV uses loopback NFS on `ubuntu-apps-dev`, which is NAS and apps host at once, and the HAOS twin.

## Layout

Declared in [`config/storage.yml`](../config/storage.yml). One directory holds everything: on the NAS it is `<export_root>/backups` (prod: `/srv/purple/backups` on Purple, bind-mounted to `/export/backups`), on the apps guest the same directory is the NFS mount `backup_root` (`/mnt/homelab/backups`).

| Stream | Runs on, by | DEV | Prod |
|--------|-------------|-----|------|
| Postgres (shared + Immich) | apps, `pg-dump.sh` (`homelab-backup.timer` 03:15) | runs | runs |
| App volumes (not media libraries) | apps, `volumes.sh` | runs | runs |
| Deployed `/opt/homelab` zip | apps, `repo-zip.sh` | runs | runs |
| rclone → `pcloud:homelab-backups` | apps, `rclone-offsite.sh`; writes `.offsite-ok` | disabled | needs `RCLONE_CONFIG` |
| Home Assistant full backup (`ha-full-*.tar`, `HA_BACKUP_PASSWORD`) | NAS, `ha-pull.sh` -> `utils/ha.py backup` (`homelab-nas-backup.timer` 02:30) | HAOS twin | needs `HA_TOKEN` |
| Home Assistant UI YAML snapshots (keep 30, only on change) | NAS, `ha-yaml.sh` -> `utils/ha.py export-ui` | HAOS twin | needs `HA_TOKEN`, `HA_SSH_PRIV` |
| OPNsense `config.xml` | NAS, `opnsense.sh`, key with a forced command | SKIP (prod only) | after `utils/f2-opnsense-backup-key.sh` |
| VM dumps 101/102 (`vzdump/dump/`) | Proxmox job `homelab-vms` 04:30 onto storage `nas-backups` (NFS `backups/vzdump`), `utils/pve-backup-job.py` | job created, disabled | runs |
| Freshness of every stream | NAS, `check-fresh.py` (`homelab-backup-check.timer` 06:00) -> Uptime Kuma push | runs | runs |

Retention **A15 = 2 newest** artefacts **per name prefix** (`linkwarden-*.sql.gz`, not “2 files in the whole folder”). `hl_prune` in `utils/backup/lib.sh`; Home Assistant: `ha.py backup --keep 2`; VM dumps: `prune-backups keep-last=2` on the Proxmox job. Max ages and the Kuma push monitors: [`config/monitoring.yml`](../config/monitoring.yml) `backups`.

Offsite is **DR only** — not Immich / Jellyfin / Navidrome libraries (those already live on pCloud separately). Media on prod is the NFS share on SA500, not a second copy in this job. A homelab backup of the media to pCloud is deferred until prod runs; the owner will adjust the pCloud targets ([decision 0002](decisions/0002-nas-layout-and-samba.md)).

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
- The router side of the OPNsense stream: `utils/f2-opnsense-backup-key.sh` (live router change, owner's decision)

## Related

- [`storage.md`](storage.md) · [`dr.md`](dr.md) · [`rebuild.md`](rebuild.md) · [`docs/f5-storage.md`](../docs/f5-storage.md)
