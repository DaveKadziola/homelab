# Easy Todo Grocery

| | |
|--|--|
| URL (dev) | http://192.168.122.50:8101 |
| Public (prod) | https://grocery.dkhomelabserver.xyz |
| Login | application users (not `homelab-admin`) |
| DB | `todo_grocery` / role `prod_todo_grocery` / `GROCERY_DB_PASSWORD` |
| Compose | `compose/grocery/` (not `compose/core`) |
| Upstream | `DaveKadziola/easytodo-grocery-list` |

Deployed automatically: `deploy-core.yml` builds the image (pinned `grocery_ref`), creates role, database and schema when missing; `utils/bootstrap/portainer.sh` creates the Portainer stack `easytodo-grocery`, or redeploys it without pulling when its container is not running.

Portainer stack `easytodo-grocery`. **Bridge** + `8101:8101` + `DB_HOST=host.docker.internal`. Upstream `network_mode: host` hides published ports in Portainer.

Env reference: [`docs/f4-apps-dev.md`](../../docs/f4-apps-dev.md).
