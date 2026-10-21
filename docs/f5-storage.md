# F5 — NAS / NFS / backups

> **Status:** implemented on DEV (loopback NFS + Samba + timer + C4 restore suite + storage suite). Prod (since 2026-10-20): SA500/Purple attached and mounted by LABEL, `RCLONE_CONFIG` in GH env `prod`, HAOS 18.3 on the T620. In code, checked on DEV, not yet released to `main` (README "Status"): HA and OPNsense streams on the NAS (`utils/backup/run-nas.sh`), VM dumps as the Proxmox job `homelab-vms` (`utils/pve-backup-job.py`), freshness to Uptime Kuma (`utils/backup/check-fresh.py`). Still the owner's: `HA_TOKEN` in env `prod`, the OPNsense backup key.  
> **Related:** [`knowledge/storage.md`](../knowledge/storage.md), [`knowledge/backup.md`](../knowledge/backup.md), [`config/storage.yml`](../config/storage.yml)

## What landed

| ID | Task | Where |
|----|------|-------|
| A1 disks | SA500 / Purple by-id, serial, slot and LABEL filled (2026-10-19); attach script: fixed slots, `serial=`, `ssd=1,discard=on` for the SSD, config validation, host pre-checks, `--dry-run`; refuses `--env` other than prod | `config/storage.yml`, `utils/pve-attach-nas-disks.sh` |
| NFS server + client | `/export` (prod) or `/srv/homelab-export` (dev) → `/mnt/homelab` | `ansible/playbooks/deploy-storage.yml` |
| NAS disks | found by serial, formatted once (blank, or the `nas_wipe` opt-in), mounted by LABEL; nfs-server stays down while a mount is missing; `crossmnt` + marker files checked by the client | `ansible/playbooks/deploy-storage.yml` |
| Samba | shares `share` + `media`, one login `admin`, SMB3, `hosts allow` LAN + WireGuard ([details](../knowledge/storage.md#samba)) | `ansible/playbooks/deploy-storage.yml` |
| Storage suite | disks, NFS markers, nfs-server guard, Samba | `tests/storage/` — part of `--suite all` |
| Backup streams | apps: pg_dump, volume tars, repo zip, rclone; NAS: HA backup + UI YAML, OPNsense; Proxmox job: VM dumps ([backup](../knowledge/backup.md)) | `utils/backup/`, `utils/pve-backup-job.py` |
| Retention A15 | keep 2 newest per stream | `utils/backup/lib.sh` `hl_prune` |
| Timer | `homelab-backup.timer` 03:15 | deploy-storage.yml |
| Prod compose binds | Immich / Jellyfin / Navidrome / Syncthing → NFS | `compose/core/docker-compose.nfs.yml` (**not** used on DEV) |
| C4 | scratch dump→restore | `tests/restore/` — `utils/run-tests.sh --env dev --suite restore` |
| HA T620 | HAOS 18.3 on the T620; packages and the full backup through `utils/ha.py` (decision 0005) | `homeassistant/README.md`, `knowledge/apps/homeassistant.md` |

## DEV vs prod

Nested PVE is ~8 GiB and `ubuntu-apps-dev` is already 6144 MiB. **Do not** Terraform-apply a 4 GiB NAS VM on nested DEV. `ubuntu_nas` in the DEV inventory is the same guest.

Ubuntu (not OMV/TrueNAS) is deliberate — see [`knowledge/storage.md`](../knowledge/storage.md#why-ubuntu-not-a-nas-distro).

## Operator (DEV)

```bash
export HOMELAB_ENV=dev
ansible-playbook -i ansible/environments/dev/hosts.ini ansible/playbooks/deploy-storage.yml
./utils/run-tests.sh --env dev --suite restore
./utils/run-tests.sh --env dev --suite storage
```

## Prod disks: run order

SA500 = all media (`/export/media`), Purple = backups + Samba share (`/srv/purple`); see [`knowledge/storage.md`](../knowledge/storage.md#prod).

1. `terraform apply` of `ubuntu-nas` (prod tfvars already describe VMID 102), then `terraform plan` - no drift.
2. `./utils/pve-attach-nas-disks.sh --env prod --dry-run`, then without `--dry-run`.
3. `terraform plan` again - no drift.
4. `deploy-storage.yml` once with the one-time wipe opt-in. A disk with a foreign signature is refused and the play lists the types it found (both prod disks held NTFS); name one per disk:
   `HOMELAB_ENV=prod ansible-playbook -i ansible/environments/prod/hosts.ini ansible/playbooks/deploy-storage.yml -e '{"nas_wipe": ["2525GTD00073:<type>", "WD-WCC7K3KZKJKX:<type>"]}'`
5. Normal deploys, without `nas_wipe`. **Never pass `nas_wipe` in CI or a DR rebuild**: a disk that already carries its LABEL is never touched.

## Still blocked on metal

1. ~~rclone OAuth~~ - done: `RCLONE_CONFIG` is in GH env **prod** only and reaches the apps host through `deploy-core.yml` `homelab_secrets`
2. ~~Flash HAOS on the T620 `.20.13`~~ - HAOS 18.3 runs; the long-lived token → `HA_TOKEN` in env `prod` is still the owner's step
3. Proxmox job `homelab-vms` (`utils/pve-backup-job.py`, run by Apps Deploy) dumps VM 101/102 onto the NAS export `backups/vzdump`

## Gate notes

F5 on DEV unblocks “we have a dump and we proved restore on a copy”. The F9 merge-to-`main` gate also needed a planned wipe and a current Bitwarden copy: wipe drill passed 2026-10-19 ([`knowledge/rebuild-drill-2026-10-19b.md`](../knowledge/rebuild-drill-2026-10-19b.md)), vault synced 2026-10-20 ([`knowledge/security.md`](../knowledge/security.md)); prod was built from `main` by release #75.
