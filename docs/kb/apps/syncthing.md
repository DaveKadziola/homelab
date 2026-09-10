# Syncthing

| | |
|--|--|
| URL (dev) | http://192.168.122.50:8384 |
| Sync | `22000/tcp+udp`, `21027/udp` |
| Login | username `admin` |
| Secret | `SYNCTHING_ADMIN_PASSWORD` |
| Bootstrap | `utils/bootstrap/syncthing.sh` |

GUI user/password are set via the API key in `config.xml`. Current Syncthing authenticates with **session login**:

`POST /rest/noauth/auth/password` → HTTP 204

HTTP basic against `/rest/system/status` returns 401 even when the password is correct.

Device IDs are generated on first start. **Peers and folders are not automated** — pair them deliberately after bootstrap. Prod compose also bind-mounts `/mnt/homelab/sync` as `HomelabSync`.
