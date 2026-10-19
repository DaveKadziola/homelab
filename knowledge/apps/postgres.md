# PostgreSQL

Shared instance for core apps. Not a login UI.

| | |
|--|--|
| Host port | `5432` |
| Superuser | `homelab` / `POSTGRES_PASSWORD` |
| Databases | `postgres-init` creates `linkwarden`, `firefly3`, `actual`, `trilium`, `grafana`, `easytodo` (same password as `POSTGRES_PASSWORD`) |
| Config-as-code | partial |

`todo_grocery` / role `prod_todo_grocery` is **not** in `postgres-init` — it was created by hand on DEV (`GROCERY_DB_PASSWORD`). Firefly and Grafana DBs are reserved; those apps are not in compose. Immich has its **own** Postgres.

Published on the host so grocery can use `host.docker.internal`. Do not expose to WAN.
