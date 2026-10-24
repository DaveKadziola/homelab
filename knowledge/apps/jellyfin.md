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

The host has no hardware transcoding (iGPU not passed through), so plays are meant to be Direct Play or Direct Stream. On prod (2026-10-23, `journalctl -k`, `/config/log/FFmpeg.*.log`), Jellyfin Web transcoded a 1080p H.264 AVI with libx264 at 0.34-0.8x of real time, and the old 512m limit OOM-killed Jellyfin twice. An H.264 MKV with AC3 audio only had its audio converted to AAC, at 7-21x. Since then `mem_limit` is 2g, and `utils/bootstrap/jellyfin.sh` sets `EnableVideoPlaybackTranscoding=false` in every user's policy (`POST /Users/{id}/Policy`); remuxing (`EnablePlaybackRemuxing`) and audio conversion stay on, so a file the client cannot decode fails instead of being re-encoded. Jellyfin for Android 2.7.3 played the same AVI as a remux (video and audio copied, 68-121x).

## Films that need a capable client

`utils/media-check.py` runs on the laptop against the Samba share (`/mnt/nas/media/video`) and lists, per file, what Jellyfin cannot pass through as it is: `remux` (H.264/HEVC in another container than MKV/MP4), `reencode` (another video codec; only reported), and notes for subtitles that need burn-in in a browser (PGS, ASS) and 10-bit HEVC. With `--apply` it remuxes the `remux` files to `<name>.mkv` next to the original (stream copy, no quality loss), checks that every stream kept all its packets and, for AVI, that frames are evenly timed, then moves the original to `media/video/_originals/<library>/...`, outside the Jellyfin libraries. Run it before adding films; delete the originals once the MKV plays well.

```bash
utils/media-check.py /mnt/nas/media/video/movies           # report
utils/media-check.py /mnt/nas/media/video/movies --apply   # remux
```

AVI keeps no presentation times for H.264 B-frames: in The Room (2003) all packets had `pts=N/A`, so Jellyfin rebuilt them (`-fflags +genpts`) on every play and the film stuttered slightly even as a remux on Jellyfin for Android. A one-time remux to MKV (2026-10-24) kept all 140737 video and 224704 audio packets, with frames every 41-42 ms. The AVI header claimed 5975 s and 143274 frames, but the streams end at 5869.8 s: compare packet counts, not the header duration. Library census the same day: 77 of 78 films MKV/MP4 with H.264 or HEVC, 1 AVI.

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
