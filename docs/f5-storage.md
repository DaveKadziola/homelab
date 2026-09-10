# F5 — NAS / NFS / backups

> **Status:** implemented on DEV (loopback NFS + timer + C4 restore suite). Prod disks, rclone OAuth, HAOS, and vzdump are not runnable from this laptop.  
> **Related:** [`kb/storage.md`](kb/storage.md), [`kb/backup.md`](kb/backup.md), [`config/storage.yml`](../config/storage.yml)

## What landed

| ID | Task | Where |
|----|------|-------|
| A1 placeholders | SA500 / Purple `by_id` empty; attach script refuses `--env` other than prod | `config/storage.yml`, `utils/pve-attach-nas-disks.sh` |
| NFS server + client | `/export` (prod) or `/srv/homelab-export` (dev) → `/mnt/homelab` | `ansible/playbooks/deploy-storage.yml` |
| Backup streams | pg_dump, volume tars, repo zip; HA / OPNsense / vzdump / rclone skip when missing | `utils/backup/` |
| Retention A15 | keep 2 newest per stream | `utils/backup/lib.sh` `hl_prune` |
| Timer | `homelab-backup.timer` 03:15 | deploy-storage.yml |
| Prod compose binds | Immich / Jellyfin / Navidrome / Syncthing → NFS | `compose/core/docker-compose.nfs.yml` (**not** used on DEV) |
| C4 | scratch dump→restore | `tests/restore/` — `utils/run-tests.sh --env dev --suite restore` |
| HA T620 | docs only — cannot flash HAOS from the laptop | `homeassistant/README.md`, `docs/kb/apps/homeassistant.md` |

## DEV vs prod

Nested PVE is ~8 GiB and `ubuntu-apps-dev` is already 6144 MiB. **Do not** Terraform-apply a 4 GiB NAS VM on nested DEV. `ubuntu_nas` in the DEV inventory is the same guest.

Ubuntu (not OMV/TrueNAS) is deliberate — see [`kb/storage.md`](kb/storage.md#why-ubuntu-not-a-nas-distro).

## Operator (DEV)

```bash
export HOMELAB_ENV=dev
ansible-playbook -i ansible/environments/dev/hosts.ini ansible/playbooks/deploy-storage.yml
./utils/run-tests.sh --env dev --suite restore
```

## Still blocked on metal

1. Physical PVE `.20.20` reachable; `ls /dev/disk/by-id` → fill `passthrough[].by_id` → `pve-attach-nas-disks.sh --env prod`
2. `terraform apply` of `ubuntu-nas` (prod tfvars already describe VMID 102)
3. rclone OAuth; store `RCLONE_CONFIG` in GH env **prod** only
4. Flash HAOS on the T620 `.20.13`; long-lived token → `HA_TOKEN`
5. Cron or manual `vzdump` on the PVE host

## Gate notes

F5 on DEV unblocks “we have a dump and we proved restore on a copy”. It does **not** pass the F9 merge-to-`main` gate (that still needs a planned wipe + Bitwarden).
