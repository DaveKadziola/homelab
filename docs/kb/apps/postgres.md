# PostgreSQL

Shared instance for core apps. Not a login UI.

| | |
|--|--|
| Host port | `5432` |
| Superuser | `homelab` / `POSTGRES_PASSWORD` |
| Databases | `homelab`, `linkwarden`, `todo_grocery`, plus reserved names in `services.yml` |
| Config-as-code | yes (`postgres-init`) |

Grocery role `prod_todo_grocery` / `GROCERY_DB_PASSWORD`. Immich has its **own** Postgres.

Published on the host so grocery can use `host.docker.internal`. Do not expose to WAN.
