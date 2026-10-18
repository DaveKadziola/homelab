# pgAdmin

| | |
|--|--|
| URL (dev) | http://192.168.122.50:5050 |
| Login | email `dev-homelabnotifications@pm.me` (prod mailbox on prod) |
| Secret | `PGADMIN_PASSWORD` |
| Bootstrap | `utils/bootstrap/pgadmin.sh` |
| Config-as-code | yes — `compose/core/pgadmin/servers.json` |

Rejects reserved TLD emails (`*.local`). Server list is reloaded on every bootstrap.

`mem_limit` must stay at **512m** — 384m OOM-kills gunicorn and `:5050` hangs.
