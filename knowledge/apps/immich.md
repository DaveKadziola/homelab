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

Scan on change (2026-10-24): Immich sees the folder over NFS and gets no change events there, so the NAS runs `homelab-photos-watch.service` (`utils/photos-watch.py`, `inotify-tools` from Ubuntu, `deploy-storage.yml`). It watches `export_root/media/photos` with `inotifywait -m -r`, and once nothing has changed for 30 s it scans every external library (`GET /api/libraries`, `POST /api/libraries/{id}/scan` against `http://<apps_host>:2283/api`). The key is `IMMICH_SCAN_API_KEY`: an API key of the Immich admin with only `library.read` and `library.update` (both endpoints are admin-only): no asset or album permission (`GET /api/albums` answers 403 with it, DEV 2026-10-24), but `library.update` also allows changing a library's paths. It lands in `/opt/homelab-nas/secrets/<env>/IMMICH_SCAN_API_KEY` and is read at each scan, so a new key needs no restart. Without it the unit stays stopped and only the 15-minute scan runs (test `storage/photos/watch`). A failed scan is logged (`journalctl -u homelab-photos-watch`) and tried again at the next change. Prod key: Immich -> Account Settings -> API Keys -> New, name `homelab-photos-scan`, permissions `library.read` and `library.update`, then `utils/gen-app-credentials.sh --env prod --secret IMMICH_SCAN_API_KEY --paste` and a deploy.

Photos uploaded through the app stay in Immich's own library; the read-only share `immich` shows them. Do not copy files into that library: Immich would not know them, and moving or deleting there breaks its database.

## More than one person (2026-10-23)

Each person has `media/photos/<username>` on the NAS and owns the external library on `/external/photos/<username>` ("NAS photos (<username>)"); the admin's is `/external/photos/admin`. `utils/bootstrap/immich.sh` creates the Immich account of every other `app: immich` account in `config/identities.yml` (`POST /api/admin/users`, storage label = username, password from its secret) and `utils/bootstrap/immich_libraries.py` keeps one library per person: it moves the old shared library (`/external/photos`, owned by the admin) to the admin's folder and scans every library on each deploy. Library endpoints are admin-only in v3.3.3. First person: `user1` (`user1@dkhomelabserver.xyz`, not a mailbox), secrets `SAMBA_USER1_PASSWORD` and `IMMICH_USER1_PASSWORD`.

Albums as folders: the storage template is `{{#if album}}{{album}}{{else}}{{y}}/{{y}}-{{MM}}-{{dd}}{{/if}}/{{filename}}`, so an uploaded photo that is in an album lands in `library/<user>/<album>/`. New uploads follow it; existing files move only when the Storage Template Migration job runs (Administration -> Jobs). On prod that job moves the 122 photos of the one album: run it deliberately, with a file list and SHA-256 before and after.

The other direction, folders on the NAS as albums: the container `immich-album-creator` (`salvoxia/immich-folder-album-creator:1.0.0`, compose profile `media`) runs at 5, 20, 35 and 50 past each hour, five minutes after the library scan. A file in `photos/<person>/<folder>/` (deeper folders included) goes into that person's album `<folder>`, created if missing (`ROOT_PATH=/external/photos`, `ALBUM_LEVELS=2,2`); a loose file in `photos/<person>/` gets no album, and photos uploaded through the app are outside `ROOT_PATH`, so the two directions do not feed each other. It only adds: `SYNC_MODE=0`, because 1 deletes every empty album (manual ones too) and 2 also deletes offline photos; an album whose folder was emptied stays in Immich. It mounts no photo folder and talks only to the Immich API, with one key per person in `/opt/homelab/secrets/immich-album-creator/api-keys` (one key per line, owner uid 1000, the image's user). `utils/bootstrap/immich_album_keys.py`, called by `immich.sh`, keeps that file: a key that still answers `GET /api/users/me` stays; a person without one logs in with their password secret and gets a new key named `homelab-album-creator` with only `asset.read`, `album.read`, `album.create`, `album.update`, `albumAsset.create` and `user.read` (no delete, nothing on accounts). Without a working login no key is made for that person (`album key <email>: no login - not created`). Checked on DEV 2026-10-24: a photo in `admin/Probe Album/` and one in `user1/Probe User1/` became one album each for their owner, a loose file got none, a second run changed nothing, users and assets stayed the same; peak memory 79 MiB. Run by hand: `docker exec -e UNATTENDED=1 homelab-core-immich-album-creator-1 /script/immich_auto_album.sh` (without `UNATTENDED` it only lists the albums it would create).
