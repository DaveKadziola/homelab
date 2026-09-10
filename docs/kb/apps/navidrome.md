# Navidrome

| | |
|--|--|
| URL (dev) | http://192.168.122.50:4533 |
| Login | username `admin` |
| Secret | `NAVIDROME_ADMIN_PASSWORD` |
| Music | `navidrome_music` volume (empty on DEV) |
| Config | `compose/core/navidrome/navidrome.toml` |
| Bootstrap | `utils/bootstrap/navidrome.sh` |

`ND_DEVAUTOCREATEADMINPASSWORD` creates `admin` **only on first start**. Later resets: `navidrome user edit --set-password` needs a TTY (`docker exec -t` + pexpect). A pipe fails with `inappropriate ioctl for device`. Copying `navidrome.db` while the process is up loses the change to WAL.
