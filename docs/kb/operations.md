# Operations

## Daily

| Task | How |
|------|-----|
| Logs | Dozzle `http://<apps>:8080` |
| Container health | `utils/run-tests.sh --env dev --suite smoke` |
| Dashboard | Homarr `:7575` (board seeded from `services.yml`) |
| Image updates | Diun (stdout / future mail) |
| Backups | `homelab-backup.timer` 03:15; `journalctl -u homelab-backup` |

## Logins (DEV)

Never copy a password into chat or a ticket. On the laptop:

```bash
# username-based apps → admin
cat ~/.homelab-secrets/dev/PORTAINER_ADMIN_PASSWORD

# email-based apps →  dev-homelabnotifications@pm.me
cat ~/.homelab-secrets/dev/IMMICH_ADMIN_PASSWORD
```

| App | URL (DEV) | Identity | Secret file |
|-----|-----------|----------|-------------|
| Portainer | http://192.168.122.50:9000 | `admin` | `PORTAINER_ADMIN_PASSWORD` |
| pgAdmin | http://192.168.122.50:5050 | env mailbox | `PGADMIN_PASSWORD` |
| Homarr | http://192.168.122.50:7575 | `admin` | `HOMARR_ADMIN_PASSWORD` |
| Authelia | https://authelia.homelab.local:9091 | `admin` | `AUTHELIA_ADMIN_PASSWORD` |
| Linkwarden | http://192.168.122.50:3001 | `admin` (or mailbox) | `LINKWARDEN_ADMIN_PASSWORD` |
| Immich | http://192.168.122.50:2283 | env mailbox | `IMMICH_ADMIN_PASSWORD` |
| Jellyfin | http://192.168.122.50:8096 | `admin` | `JELLYFIN_ADMIN_PASSWORD` |
| Navidrome | http://192.168.122.50:4533 | `admin` | `NAVIDROME_ADMIN_PASSWORD` |
| Syncthing | http://192.168.122.50:8384 | `admin` | `SYNCTHING_ADMIN_PASSWORD` |
| Beszel | http://192.168.122.50:8090 | env mailbox | `BESZEL_ADMIN_PASSWORD` |
| Grocery | http://192.168.122.50:8101 | none (app users) | `GROCERY_DB_PASSWORD` for the DB role |

Authelia: accept the self-signed cert; use the **name**, not the IP. See [`networking.md`](networking.md).

## Add an app

1. Declare it in `config/services.yml` (port, check, dashboard group).
2. Add the compose service (no secret fallbacks).
3. If it has an admin: account in `identities.yml` + `utils/bootstrap/<app>.sh`.
4. `docs/kb/apps/<app>.md`.
5. Smoke picks it up from `services.yml`.

## Rotate / recover

See [`security.md`](security.md) and the per-app page. Destructive volume wipes are DEV-only.

## Tests

```bash
./utils/run-tests.sh --env dev --suite all
```

`SKIP` is not a failure. Infra plan FAILs only if Terraform would **replace** a VM.

F5 restore (scratch DB, not `--suite all`):

```bash
./utils/run-tests.sh --env dev --suite restore
```
