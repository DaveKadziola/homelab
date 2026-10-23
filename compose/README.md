# compose

| Path | Does |
| --- | --- |
| `core/docker-compose.yml` | The apps on the apps VM, one service per directory next to it where that app has its own files |
| `core/docker-compose.nfs.yml` | Prod only. Binds media libraries to the NAS. Dev keeps the named volumes |
| `core/caddy/` | Image build for the proxy. The Caddyfile is generated at deploy by `utils/gen-proxy-config.py` |
| `core/authelia/` | Login in front of the app names. Access rules are generated at deploy |
| `core/diun/diun.yml` | Which images to watch. Mail settings are written at deploy, not stored here |
| `core/homarr/board-*.json` | A seed. The board deployed to the host is regenerated from `config/services.yml` |
| `core/immich/`, `core/navidrome/`, `core/pgadmin/` | App config that is not secret |
| `grocery/docker-compose.yml` | Public Grocery list. Deploy builds its image from the grocery repo and starts it through Portainer |

Ports, profiles, and health checks are `config/services.yml`. This directory does not declare them a second time.

Compose interpolates `${VAR:?}` in every service, including services of a profile that is off, so `.env` must define it in every environment (compose v5.6.1, 2026-10-23).
