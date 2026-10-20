# Beszel

| | |
|--|--|
| URL (dev) | http://192.168.122.50:8090 |
| Login | email `dev-homelabnotifications@pm.me` |
| Secret | `BESZEL_ADMIN_PASSWORD` |
| Bootstrap | `utils/bootstrap/beszel.sh` |
| Auth API | `POST /api/collections/_superusers/auth-with-password` |

Bootstrap upserts the hub superuser (`beszel superuser upsert`, distroless image) and then runs `utils/bootstrap/beszel_config.py`. It creates the Beszel user with the same login (role admin), the system `<env>-apps` owned by it, the alerts from `config/monitoring.yml` (CPU 80% for 15 min, memory 90% for 10 min, disk 80%), the alert mail to `environment_email`, and the hub SMTP from `config/monitoring.yml` (DEV: mailpit; prod: Proton SMTP with `SMTP_USERNAME`/`SMTP_PASSWORD`, without them it only warns).

The agent key and token are issued by the hub and never leave the apps host: bootstrap writes `/opt/homelab/compose/core/beszel-agent.env` (`KEY`, `TOKEN`) and starts `beszel-agent` (profile `beszel-agent`, host net), which connects to the hub over WebSocket. Beszel 0.21 needs `users` on a system record (a POST without it returns HTTP 400) and `/api/beszel/getkey` needs an auth token (DEV, 2026-10-20). One alert per metric and system: `disk_percent_critical` has no Beszel alert.
