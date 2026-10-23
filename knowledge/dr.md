# Disaster recovery

DR here means “the building burned / the disk died / I bought new hardware”, not “restart a container”.

## What you can recover today

| Asset | How |
|-------|-----|
| Repo + IaC | git (`develop` / `main`) |
| Secret *names* | [`docs/secrets-inventory.md`](../docs/secrets-inventory.md) · `config/identities.yml` |
| Secret *values* | Bitwarden (mandatory). GH cannot give them back. |
| Nested DEV VMs | `utils/ensure-dev-proxmox.sh` + `utils/dev-apply-local.sh` + Ansible |
| Authelia hash | committed `users_database.yml` + `utils/bootstrap/authelia.sh` |
| Postgres (DEV) | `pg_dump` under `/mnt/homelab/backups/postgres` + `utils/backup/restore-pg.sh` |
| Small app volumes (DEV) | tars under `/mnt/homelab/backups/volumes` |

`tests/restore/` proves a **scratch** database dump→restore. It does not restore Immich photos.

## What you cannot recover yet

- Samba share and media — no homelab copy yet: the share (Purple) is never backed up, the media (SA500) pCloud backup is deferred ([decision 0002](decisions/0002-nas-layout-and-samba.md))
- Offsite pCloud copy — only if `rclone-offsite.sh` ran on prod (`.offsite-ok` in `/mnt/homelab/backups`); `RCLONE_CONFIG` is in GH env `prod` and reaches the apps host through `deploy-core.yml` `homelab_secrets`
- Home Assistant — only if the NAS stream `ha-pull.sh` ran (`ha-full-*.tar`); HAOS 18.3 runs on the T620, but without `HA_TOKEN` in environment `prod` the stream skips (`utils/backup/ha-pull.sh:13-14`)
- VM dumps of prod — only if the Proxmox job `homelab-vms` ran (`/export/backups/vzdump/dump/` on the NAS, [backup](backup.md))
- OPNsense live config — unless the NAS stream `opnsense.sh` ran (`/export/backups/opnsense/`) or you exported `config.xml` yourself

## Order after a total loss

Follow [`rebuild.md`](rebuild.md). After F7 bootstrap: restore Postgres dumps, then volume tars, then media from NFS/pCloud, then HA `.tar` if you have one. Then HAProxy and `utils/run-tests.sh`.

Never pass `nas_wipe` to `deploy-storage.yml` in a rebuild: a surviving disk that carries its LABEL is mounted as it is.

The F9 nested-PVE wipe drill passed on 2026-10-19 with no code change ([`rebuild-drill-2026-10-19b.md`](rebuild-drill-2026-10-19b.md)); prod was built from `main` by release #75 (2026-10-20).

## Related

- [`backup.md`](backup.md) · [`rebuild.md`](rebuild.md)
