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

## Related

- [`backup.md`](backup.md) · [`dr.md`](dr.md) · [`docs/f5-storage.md`](../f5-storage.md)
