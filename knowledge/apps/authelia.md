# Authelia

| | |
|--|--|
| URL (dev) | https://authelia.homelab.local:9091 (self-signed) |
| Login | username `admin` |
| Secret | `AUTHELIA_ADMIN_PASSWORD` |
| Also | `AUTHELIA_JWT_SECRET`, `AUTHELIA_SESSION_SECRET`, `AUTHELIA_STORAGE_KEY` |
| Users file | `compose/core/authelia/users_database.yml` (argon2id hash, committable) |
| Bootstrap | `utils/bootstrap/authelia.sh` |
| Profile | `auth` |

Cookie domain is `homelab.local`. First-factor against a raw IP fails or does not keep a session. Client `/etc/hosts`:

```
192.168.122.50 authelia.homelab.local homelab.local
```

Bootstrap check uses `curl --resolve authelia.homelab.local:9091:127.0.0.1`.
