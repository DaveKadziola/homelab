# Disaster recovery

DR here means “the building burned / the disk died / I bought new hardware”, not “restart a container”.

## What you can recover today

| Asset | How |
|-------|-----|
| Repo + IaC | git (`homelab-v2` / `main`) |
| Secret *names* | [`docs/secrets-inventory.md`](../docs/secrets-inventory.md) · `config/identities.yml` |
| Secret *values* | Bitwarden (mandatory). GH cannot give them back. |
| Nested DEV VMs | `utils/ensure-dev-proxmox.sh` + `utils/dev-apply-local.sh` + Ansible |
| Authelia hash | committed `users_database.yml` + `utils/bootstrap/authelia.sh` |
| Postgres (DEV) | `pg_dump` under `/mnt/homelab/backups/postgres` + `utils/backup/restore-pg.sh` |
| Small app volumes (DEV) | tars under `/mnt/homelab/backups/volumes` |

`tests/restore/` proves a **scratch** database dump→restore. It does not restore Immich photos.

## What you cannot recover yet

- Prod NAS contents — SA500/Purple are known (`config/storage.yml`: serial, by-id, slot, label) but not attached or formatted yet
- Samba share and media — no homelab copy yet: the share (Purple) is never backed up, the media (SA500) pCloud backup is deferred ([decision 0002](decisions/0002-nas-layout-and-samba.md))
- Offsite pCloud copy — `RCLONE_CONFIG` is not in GH prod
- Home Assistant — T620 is not HAOS from this repo; `HA_TOKEN` unset
- vzdump of prod VMs — script skips unless it runs on physical PVE
- OPNsense live config — unless `opnsense.sh` reached the router or you exported `config.xml` yourself

## Order after a total loss

Follow [`rebuild.md`](rebuild.md). After F7 bootstrap: restore Postgres dumps, then volume tars, then media from NFS/pCloud, then HA `.tar` if you have one. Then HAProxy and `utils/run-tests.sh`.

Never pass `nas_wipe` to `deploy-storage.yml` in a rebuild: a surviving disk that carries its LABEL is mounted as it is.

A nested-PVE **wipe** on the laptop is still the F9 merge gate. F5 on DEV is not that wipe.

## Related

- [`backup.md`](backup.md) · [`rebuild.md`](rebuild.md)
