# Homarr

| | |
|--|--|
| URL (dev) | http://192.168.122.50:7575 |
| Login | username `admin` |
| Secret | `HOMARR_ADMIN_PASSWORD` |
| Also | `HOMARR_SECRET_KEY` (encryption, not the login) |
| Volume | `homelab-core_homarr_data` (`/appdata/db/db.sqlite`) |
| Bootstrap | `utils/bootstrap/homarr.sh` (board seed; password CLI is skipped) |
| Config-as-code | partial — board from `utils/gen-homarr-board.sh` |

`homarr-cli` (`users list` / `update-password`) **hangs** on this image. Do not pass the password on the host `docker exec` argv — it leaked once and was rotated.

Password is stored as bcrypt in sqlite. If login fails after a rotation, set it once in the UI or update the `user.password` hash and restart the container.

Board tiles come from `config/services.yml` `dashboard:` groups, plus a Home Assistant
tile from `config/storage.yml` `environments.<env>.ha_url` (the same URL as `utils/ha.py`).
HA is not a `services.yml` row. The prod tile has no ping: the apps host cannot reach
the T620 on IOT.

The seed on the host is written by every deploy ("Write the Homarr board seed",
`ansible/playbooks/deploy-core.yml:230`) from `config/services.yml` and the profiles that deploy
enables, so `compose/core/homarr/board-<env>.json` in git can lag behind it; regenerate with
`./utils/gen-homarr-board.sh --env <env>`. A tile links to the service `path` unless it starts with
`/api` or `/health` (then `/`); the ping always uses `path`.
