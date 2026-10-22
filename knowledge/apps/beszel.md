# Beszel

| | |
|--|--|
| URL (dev) | http://192.168.122.50:8090 |
| Login | email `dev-homelabnotifications@pm.me` |
| Secret | `BESZEL_ADMIN_PASSWORD` |
| Bootstrap | `utils/bootstrap/beszel.sh` |
| Auth API | `POST /api/collections/_superusers/auth-with-password` |

Bootstrap upserts the hub superuser (`beszel superuser upsert`, distroless image) and then runs `utils/bootstrap/beszel_config.py`. It creates the Beszel user with the same login (role admin), the system `<env>-apps` owned by it, the alerts from `config/monitoring.yml` (CPU 80% for 15 min, memory 90% for 10 min, disk 80%), the alert mail to `environment_email`, and the hub SMTP from `config/monitoring.yml` (DEV: mailpit; prod: Proton SMTP with `SMTP_USERNAME`/`SMTP_PASSWORD`, without them it only warns).

The agent key and token are issued by the hub and never leave the apps host: bootstrap writes `/opt/homelab/compose/core/beszel-agent.env` (`KEY`, `TOKEN`) and starts `beszel-agent` (profile `beszel-agent`, host net), which connects to the hub over WebSocket. `prod-nas` (192.168.20.12) and `prod-pve` (192.168.20.20) are hub systems too. Each runs `beszel-agent` 0.21.0 from the upstream install script (`-v 0.21.0 --auto-update=false`), listening on 45876 and dialing `http://192.168.50.30:8090`. Both were `up` on 2026-10-22. The hub records are listed in `config/monitoring.yml` `beszel_agents`. `prod-hass` (192.168.20.13) uses the add-on from `https://github.com/matthewhadley/homeassistant-beszel-agent` (agent 0.21.0, slug `646f01c8_beszel-agent`), one of the three repositories in the Beszel Home Assistant guide. It was `up` on 2026-10-22. The add-on is not installed by `utils/ha.py`. Beszel 0.21 needs `users` on a system record (a POST without it returns HTTP 400) and `/api/beszel/getkey` needs an auth token (DEV, 2026-10-20). One alert per metric and system: `disk_percent_critical` has no Beszel alert.
