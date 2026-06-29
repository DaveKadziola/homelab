# Application sources — gate A16

> **Status:** [x] ✅ 2026-06-11 — **20/20** verified (`gh api repos/<owner>/<repo>`)  
> **Related:** greenfield v2 plan section *Application repo verification*, P0/P1/P2 inventory

Verification: repositories exist, `archived=false`. Deploy: mostly via Docker Hub/GHCR; **Easy Todo Grocery** via Portainer Git deploy from the user's own repo.

## P0

| Application | GitHub | Last push | Deploy / image | Notes |
|-------------|--------|-----------|----------------|-------|
| PostgreSQL | [postgres/postgres](https://github.com/postgres/postgres) | 2026-06-11 | Docker Hub `postgres` | Shared instance; separate DB per app |
| pgAdmin | [pgadmin-org/pgadmin4](https://github.com/pgadmin-org/pgadmin4) | 2026-06-11 | Docker Hub `dpage/pgadmin4` | VPN-only |
| Homarr | [homarr-labs/homarr](https://github.com/homarr-labs/homarr) | 2026-06-11 | GHCR / compose | Dashboard + shortcuts |
| Trillium (Trilium) | [TriliumNext/Trilium](https://github.com/TriliumNext/Trilium) | 2026-06-11 | Docker Hub `triliumnext/trilium` | Plan: "Trillium"; fork from `zadam/trilium` |
| Actual Budget | [actualbudget/actual](https://github.com/actualbudget/actual) | 2026-06-11 | GHCR / compose | Postgres |
| Linkwarden | [linkwarden/linkwarden](https://github.com/linkwarden/linkwarden) | 2026-06-09 | GHCR / compose | ~~linkwarden-app/linkwarden~~ → 404 |
| Authelia | [authelia/authelia](https://github.com/authelia/authelia) | 2026-06-11 | GHCR `authelia/authelia` | SSO forward-auth |
| omni-tools | [iib0011/omni-tools](https://github.com/iib0011/omni-tools) | 2026-05-04 | compose / GHCR | VPN only |
| DumbWhoIs | [DumbWareio/DumbWhoIs](https://github.com/DumbWareio/DumbWhoIs) | 2026-02-02 | compose | [dumbware.io](https://www.dumbware.io/DumbWhoIs) |
| Bento PDF | [alam00000/bentopdf](https://github.com/alam00000/bentopdf) | 2026-06-09 | compose | Plan: "Bentoo PDF" |
| Portainer | [portainer/portainer](https://github.com/portainer/portainer) | 2026-06-11 | Docker Hub `portainer/portainer-ce` | Multi-repo stacks |
| Easy Todo Grocery | [DaveKadziola/easytodo-grocery-list](https://github.com/DaveKadziola/easytodo-grocery-list) | 2025-03-15 | **Portainer Git deploy** | Public HTTPS; own repo (A11) |

## P1

| Application | GitHub | Last push | Deploy / image | Notes |
|-------------|--------|-----------|----------------|-------|
| Immich | [immich-app/immich](https://github.com/immich-app/immich) | 2026-06-11 | GHCR | NFS SA500; cap 60 GB prod |
| Syncthing | [syncthing/syncthing](https://github.com/syncthing/syncthing) | 2026-06-11 | Docker Hub `syncthing/syncthing` | LAN sync |
| Navidrome | [navidrome/navidrome](https://github.com/navidrome/navidrome) | 2026-06-11 | Docker Hub `deluan/navidrome` | cap 150 GB prod |
| Jellyfin | [jellyfin/jellyfin](https://github.com/jellyfin/jellyfin) | 2026-06-11 | GHCR | Direct play only; cap 400 GB prod |

## P2

| Application | GitHub | Last push | Deploy / image | Notes |
|-------------|--------|-----------|----------------|-------|
| Beszel | [henrygd/beszel](https://github.com/henrygd/beszel) | 2026-06-08 | compose | Metrics (B19) |
| Diun | [crazy-max/diun](https://github.com/crazy-max/diun) | 2026-06-11 | Docker Hub `crazymax/diun` | Image update notify (B20) |
| Dozzle | [amir20/dozzle](https://github.com/amir20/dozzle) | 2026-06-11 | Docker Hub `amir20/dozzle` | Container logs |
| Zotify | [Googolplexed0/zotify](https://github.com/Googolplexed0/zotify) | 2026-05-12 | Python / compose | defer (B13) |

## Corrections vs earlier URLs in the plan

| App | Wrong URL | Correct URL |
|-----|-----------|-------------|
| Trillium | `zadam/trilium` (redirect) | `TriliumNext/Trilium` |
| Linkwarden | `linkwarden-app/linkwarden` (404) | `linkwarden/linkwarden` |
| Grocery | TBD | `DaveKadziola/easytodo-grocery-list` |

## Unresolved

None — all apps from the P0/P1/P2 inventory have a confirmed source.
