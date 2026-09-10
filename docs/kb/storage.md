# Storage

Layout and env modes live in [`config/storage.yml`](../../config/storage.yml). Ansible: `ansible/playbooks/deploy-storage.yml`.

## Dev (`ubuntu-apps-dev`)

Nested PVE has ~8 GiB RAM and the apps guest is already 6 GiB — there is **no second NAS VM**.

- Export tree: `/srv/homelab-export/{media,sync,backups}`
- NFS loopback: `192.168.122.50:/srv/homelab-export` → `/mnt/homelab`
- App **libraries stay on Docker named volumes**. The NFS compose override is **not** applied on DEV (that would hide Immich photos).

Notable volumes (compose project `homelab-core`):

| Volume | App |
|--------|-----|
| `*_postgres_data` | shared Postgres |
| `*_immich_postgres` / `*_immich_upload` / `*_immich_model_cache` | Immich |
| `*_jellyfin_config` / `*_jellyfin_media` | Jellyfin |
| `*_navidrome_data` / `*_navidrome_music` | Navidrome |
| `*_portainer_data` | Portainer |
| `*_homarr_data` | Homarr |
| `*_syncthing_data` | Syncthing |

Wiping a volume is a DEV-only recovery tool (see [`apps/jellyfin.md`](apps/jellyfin.md)). Never do this on prod.

## Prod

| Disk | Role | How |
|------|------|-----|
| SA500 | NFS media (Immich / Jellyfin / Navidrome) | Fill `passthrough[].by_id`, then `utils/pve-attach-nas-disks.sh --env prod`. Do not invent by-id. |
| Purple | backup target (`/export/backups`) | same script, role `backups` |
| apps 48G | images + small state | TF sized, not applied yet |

`ubuntu-nas` `.20.12` exports `/export`. `ubuntu-apps` `.50.30` mounts it at `/mnt/homelab`. Compose then uses [`compose/core/docker-compose.nfs.yml`](../../compose/core/docker-compose.nfs.yml).

Firewall APP → NAS `:2049` / `:111` is an F2 rule — see [`docs/network.md`](../network.md).

## Why Ubuntu, not a NAS distro

`ubuntu-nas` is a **thin NFS exporter**, not a home NAS appliance. The guest has one job: pass through SA500 + Purple and export `/export` to `ubuntu-apps`. Docker, Postgres, Immich, and the backup timer already live on the apps VM. Decision **B6/B7**: 4 GiB RAM for NAS next to 8 GiB apps on a Celeron J4205.

A dedicated distro would solve a different problem (SMB for many clients, a web UI, ZFS pools, plugins). It would not make F5 smaller.

| Option | Fit here | Why not (today) |
|--------|----------|-----------------|
| **Ubuntu cloud image** (current) | Same Terraform, cloud-init, SSH, and Ansible as `ubuntu-apps`. `nfs-kernel-server` + `/etc/exports` is the whole NAS role. | — |
| **OpenMediaVault** | Debian, lighter than TrueNAS, decent UI. | Config lives in the OMV UI / salt, not `config/storage.yml`. Second image, second admin account, same NFS at the end. DEV still cannot run a second VM. |
| **TrueNAS** (CORE / SCALE; formerly FreeNAS) | Real ZFS (scrub, snapshots) if you have the RAM. | ZFS ARC wants far more than **4 GiB**. Second OS family, different updates and DR than the rest of the IaC. Two pass-through disks and ~739 GB hot data do not pay for that. |

Keep Ubuntu until one of the triggers below is true. Do not swap distros “because NAS products exist”.

### When to move to a NAS distro

Revisit only if several of these land:

1. A third / fourth disk and you actually want **ZFS** (mirrors, scrub, snapshots) rather than two independent volumes.
2. Many **SMB/AFP clients** (TVs, Windows laptops) — not just one apps VM on NFS.
3. You would rather operate storage from a **UI** than from git + Ansible.
4. The NAS RAM budget grows well above 4 GiB (TrueNAS), or you accept OMV’s UI as the source of truth.

If you switch: replace the **guest OS** only. Keep IP **`192.168.20.12`**, VLAN 20, the `/export` layout, and APP→NAS `:2049`. Then OMV, not TrueNAS, unless the host has been upsized. Nested DEV stays loopback NFS on `ubuntu-apps-dev`.

## Related

- [`backup.md`](backup.md) · [`dr.md`](dr.md) · [`docs/f5-storage.md`](../f5-storage.md)
