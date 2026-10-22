# Authelia

| | |
|--|--|
| URL | `https://auth.<domain>` through Caddy: DEV `https://auth.dev.dkhomelabserver.xyz` (Caddy's internal CA), prod `https://auth.dkhomelabserver.xyz` (Let's Encrypt) |
| Login | username `admin` |
| Secret | `AUTHELIA_ADMIN_PASSWORD` |
| Also | `AUTHELIA_JWT_SECRET`, `AUTHELIA_SESSION_SECRET`, `AUTHELIA_STORAGE_KEY` |
| Users file | `compose/core/authelia/users_database.yml` (argon2id hash, committable) |
| Bootstrap | `utils/bootstrap/authelia.sh` |
| Profile | `auth`, together with `proxy` (Caddy) on DEV and prod; prod enables both only when `CLOUDFLARE_API_TOKEN` is in environment `prod` ([decision 0007](../decisions/0007-app-names-caddy-authelia.md)) |

Authelia listens on plain HTTP `:9091` behind Caddy, which asks it (`/api/authz/forward-auth`) for every app name except the paths a service lists in `auth_bypass` (`compose/core/authelia/configuration.yml`, `utils/gen-proxy-config.py`). The session cookie domain (`environments.<env>.domain` in `config/services.yml`) and the access rules are generated at deploy into `compose/core/authelia/access.yml` (`ansible/playbooks/deploy-core.yml`). A login by IP does not keep a session: use the name. Names resolve through the AdGuard rewrites (`utils/adguard-rewrites.sh`, owner's decision); until those exist, add them to the laptop `/etc/hosts` ([`docs/f4-apps-dev.md`](../../docs/f4-apps-dev.md)):

```
192.168.122.50 auth.dev.dkhomelabserver.xyz homarr.dev.dkhomelabserver.xyz
```

Bootstrap check posts to the container on `127.0.0.1:9091` with `X-Forwarded-Host: auth.<domain>`, as Caddy does (`utils/bootstrap/authelia.sh:27-29`). The smoke suite checks the redirect to Authelia per app name and one login (`proxy/*` in `tests/smoke/run.sh`); `utils/run-tests.sh --env dev --suite smoke`, 2026-10-21: 113 PASS including the proxy checks.
