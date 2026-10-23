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

Photos the owner adds, renames or deletes in the Samba share `photos` (`export_root/media/photos` on the NAS) show up in Immich as the external library "NAS photos". `immich-server` mounts that folder read-only at `/external/photos` (`compose/core/docker-compose.yml`), so Immich never changes or deletes those files. `utils/bootstrap/immich.sh` creates the library once (`POST /api/libraries`, owner: the admin) and queues a scan on every deploy; Immich also rescans every 15 minutes (`library.scan.cronExpression` `*/15 * * * *` in `compose/core/immich/system-config.json`), or at once with "Scan" under Administration -> External Libraries. A file deleted from the share leaves the Immich timeline after the next scan. Checked on DEV 2026-10-23: a JPEG put over Samba (same SHA-256 on the laptop and in `media/photos`) became one asset of "NAS photos" after a scan, and went offline after it was deleted over Samba and scanned again. For an external library Immich's `checksum` is SHA-1 of `path:<originalPath>`, not of the file, so compare file contents with `sha256sum` on the NAS.

Photos uploaded through the app stay in Immich's own library; the read-only share `immich` shows them. Do not copy files into that library: Immich would not know them, and moving or deleting there breaks its database.

## More than one person (2026-10-23)

Each person has `media/photos/<username>` on the NAS and owns the external library on `/external/photos/<username>` ("NAS photos (<username>)"); the admin's is `/external/photos/admin`. `utils/bootstrap/immich.sh` creates the Immich account of every other `app: immich` account in `config/identities.yml` (`POST /api/admin/users`, storage label = username, password from its secret) and `utils/bootstrap/immich_libraries.py` keeps one library per person: it moves the old shared library (`/external/photos`, owned by the admin) to the admin's folder and scans every library on each deploy. Library endpoints are admin-only in v3.3.3. First person: `user1` (`user1@dkhomelabserver.xyz`, not a mailbox), secrets `SAMBA_USER1_PASSWORD` and `IMMICH_USER1_PASSWORD`.

Albums as folders: the storage template is `{{#if album}}{{album}}{{else}}{{y}}/{{y}}-{{MM}}-{{dd}}{{/if}}/{{filename}}`, so an uploaded photo that is in an album lands in `library/<user>/<album>/`. New uploads follow it; existing files move only when the Storage Template Migration job runs (Administration -> Jobs). On prod that job moves the 122 photos of the one album: run it deliberately, with a file list and SHA-256 before and after.
