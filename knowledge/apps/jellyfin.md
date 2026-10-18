# Jellyfin

| | |
|--|--|
| URL (dev) | http://192.168.122.50:8096 |
| Login | username `admin` |
| Secret | `JELLYFIN_ADMIN_PASSWORD` |
| Volumes | `jellyfin_config`, `jellyfin_cache`, `jellyfin_media` |
| Bootstrap | `utils/bootstrap/jellyfin.sh` |
| Profile | `media` |

The `/Startup/*` wizard runs **once**. After `StartupWizardCompleted=true` there is no supported CLI password reset.

On this DEV guest the first wizard created user **`root`**. It was renamed to `admin` and the password set to the secret cache (PBKDF2-SHA512 in `jellyfin.db`). `/Users/Public` can still return `[]` even when `admin` exists.

Since 12.2.0 (DEV, 2026-10-19) a fresh server has no user. `GET /Startup/User` creates `root` (log: "No users, creating one with username root"), and `POST /Startup/User` answers 404 until that call. Bootstrap calls the GET first, the same order the web wizard uses. `StartupRemoteAccessDto` only accepts `EnableRemoteAccess`.

Libraries declared in `config/services.yml` (`Movies` / `Shows` / `Music` under `/media/…`) are created by bootstrap when login works.

Since 12.0.0 the API rejects the legacy `X-Emby-Token` header and the `api_key` query with 401 and an empty body; send the token as `Authorization: MediaBrowser ..., Token="<token>"` (verified on DEV 2026-10-18).

## Recover on DEV (destructive)

```bash
ssh -i ~/.ssh/homelab_dev_ed25519 ubuntu-dev@192.168.122.50 \
  'cd /opt/homelab/compose/core && docker compose stop jellyfin
   docker volume rm homelab-core_jellyfin_config
   docker compose --profile media up -d jellyfin'
./utils/bootstrap/jellyfin.sh --env dev --host 192.168.122.50
```

On prod: reset in the UI, then
`utils/gen-app-credentials.sh --env prod --secret JELLYFIN_ADMIN_PASSWORD --rotate`.
