# Immich

| | |
|--|--|
| URL (dev) | http://192.168.122.50:2283 |
| Login | email `dev-homelabnotifications@pm.me` |
| Secret | `IMMICH_ADMIN_PASSWORD` |
| DB | dedicated Immich Postgres (`IMMICH_DB_PASSWORD`) |
| Bootstrap | `utils/bootstrap/immich.sh` |
| Profile | `media` |

A fresh install has no user (`GET /api/server/config` -> `isInitialized:false`). Bootstrap creates the declared admin with `POST /api/auth/admin-sign-up` (`email`, `password`, `name`; answers only while not initialized). The account starts with `shouldChangePassword=true`, which bootstrap clears (verified on DEV v3.3.3, 2026-10-19).

DEV stores the library on **local Docker volumes**, not NFS. HTTP login returns **201**.

`immich-admin reset-admin-password` ignores a pipe (no TTY). Bootstrap drives it with pexpect. The host needs `python3-pexpect`.

Machine-learning needs `cpu_type=host` on the VM. Immich Postgres `mem_limit` ≥ 768m.

Prod target: NFS on SA500 via `compose/core/docker-compose.nfs.yml` (after `deploy-storage.yml`). DEV must keep the named volume.
