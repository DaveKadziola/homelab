# Backup

**Status:** F5 is not implemented. There is no scheduled `pg_dump`, no volume snapshot job, and no rclone/pCloud push from this repo.

## What should exist (target)

| Data | Method | Destination |
|------|--------|-------------|
| Postgres DBs (`homelab`, `linkwarden`, `todo_grocery`, …) | `pg_dump` per database | Purple / offsite |
| Immich library | filesystem / NFS snapshot | SA500 + offsite |
| Jellyfin / Navidrome libraries | NFS on SA500 | already “the copy” |
| App volumes (Portainer, Homarr, Trilium, Actual, Syncthing) | volume tar or restic | Purple |
| OPNsense | `config.xml` export | Bitwarden + this repo’s `opnsense/backups/` (gitignored) |
| Authelia users file | already in git (hash only) | — |

`tests/restore/` (F7-C C4) is deferred until these jobs exist. Do not claim a restore test passes.

## Operator copies that are not backups

- `~/.homelab-secrets/<env>/` — credential cache, not app data
- Bitwarden `homelab/<NAME>/<env>` — the durable secret store
- GitHub Environment secrets — write-only; cannot be read back

## Related

- [`dr.md`](dr.md) · [`rebuild.md`](rebuild.md)
