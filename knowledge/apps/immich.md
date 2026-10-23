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

## Photos from the NAS (external library, 2026-10-23)

Photos the owner adds, renames or deletes in the Samba share `photos` (`export_root/media/photos` on the NAS) show up in Immich as the external library "NAS photos". `immich-server` mounts that folder read-only at `/external/photos` (`compose/core/docker-compose.yml`), so Immich never changes or deletes those files. `utils/bootstrap/immich.sh` creates the library once (`POST /api/libraries`, owner: the admin) and queues a scan on every deploy; Immich also rescans hourly (`library.scan.cronExpression` in `compose/core/immich/system-config.json`), or at once with "Scan" under Administration -> External Libraries. A file deleted from the share leaves the Immich timeline after the next scan.

Photos uploaded through the app stay in Immich's own library; the read-only share `immich` shows them. Do not copy files into that library: Immich would not know them, and moving or deleting there breaks its database.
