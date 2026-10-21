# PostgreSQL

Shared instance for core apps. Not a login UI.

| | |
|--|--|
| Host port | `5432` |
| Superuser | `homelab` / `POSTGRES_PASSWORD` |
| Databases | `postgres-init` creates `linkwarden`, `firefly3`, `actual`, `trilium`, `grafana`, `easytodo` (same password as `POSTGRES_PASSWORD`) |
| Config-as-code | partial |

`easytodo` (Grocery v2) comes from `postgres-init`; `deploy-core.yml` gives role `easytodo` its own password (`GROCERY_DB_PASSWORD`). `todo_grocery` / role `prod_todo_grocery` is the v1 database, left in place. Firefly and Grafana DBs are reserved; those apps are not in compose. Immich has its **own** Postgres.

Published on the host so grocery can use `host.docker.internal`. Do not expose to WAN.
