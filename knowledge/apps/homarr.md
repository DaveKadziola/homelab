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

Board tiles come from `config/services.yml` `dashboard:` groups, plus tiles that are not
services. Prod Home Assistant opens `http://hass.dkhomelabserver.xyz/` (the AdGuard
rewrite). DEV still uses `config/storage.yml` `ha_url`. Prod also links Proxmox
(`:8006`), AdGuard, the switch and the access point. None of those are pinged: the
apps host cannot reach the T620 or the LAN addresses.

The seed on the host is written by every deploy ("Write the Homarr board seed",
`ansible/playbooks/deploy-core.yml:230`) from `config/services.yml` and the profiles that deploy
enables, so `compose/core/homarr/board-<env>.json` in git can lag behind it; regenerate with
`./utils/gen-homarr-board.sh --env <env>`. A tile links to the service `path` unless it starts with
`/api` or `/health` (then `/`); the ping always uses `path`.
