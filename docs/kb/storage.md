# Storage

## Dev (`ubuntu-apps-dev`)

Everything lives on the guest disk (27G `local-lvm`) as Docker named volumes. There is **no NFS**. Immich media is local on purpose so a nested lab does not depend on SA500.

Notable volumes (compose project `homelab-core`):

| Volume | App |
|--------|-----|
| `*_postgres_data` | shared Postgres |
| `*_immich_postgres` / `*_immich_data` / `*_immich_ml` | Immich |
| `*_jellyfin_config` / `*_jellyfin_media` | Jellyfin |
| `*_navidrome_data` / `*_navidrome_music` | Navidrome |
| `*_portainer_data` | Portainer |
| `*_homarr_data` | Homarr |
| `*_syncthing_data` | Syncthing |
| `*_zotify_config` | Zotify OAuth |

Wiping a volume is a DEV-only recovery tool (see [`apps/jellyfin.md`](apps/jellyfin.md)). Never do this on prod.

## Prod (planned — F5)

| Disk | Role | Status |
|------|------|--------|
| SA500 | NFS media (Immich / Jellyfin / Navidrome) | A1 mount **not implemented** |
| Purple | backup target | **not implemented** |
| apps 48G | images + small state | TF sized, not applied |

Until F5 lands, treat prod media and backups as **not rebuildable from this repo**.

## Related

- [`backup.md`](backup.md) · [`dr.md`](dr.md)
