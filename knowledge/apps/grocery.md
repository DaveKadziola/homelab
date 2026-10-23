Status: draft
Last reviewed: 2026-10-23
Scope: EasyToDo Grocery on DEV and prod - build, stack, proxy, upstream releases

# Easy Todo Grocery (EasyToDo v2)

| | |
|--|--|
| URL (dev) | http://192.168.122.50:8101 |
| Public (prod) | https://grocery.dkhomelabserver.xyz |
| Login | e-mail accounts of the app; admin = `homelab-admin` mailbox, `GROCERY_ADMIN_PASSWORD` |
| Registration | closed; people join through invite links |
| DB | `easytodo` / role `easytodo` / `GROCERY_DB_PASSWORD` (core Postgres, daily dump) |
| Mail | Proton SMTP as `todo-grocery@dkhomelabserver.xyz` with `GROCERY_PROTON_SMTP_TOKEN`; without the token the console backend (links in the app log) |
| Compose | `compose/grocery/` (not `compose/core`) |
| Upstream | `DaveKadziola/easytodo-grocery-list`, pinned by `grocery_ref` in `deploy-core.yml` |

Deployed automatically: `deploy-core.yml` builds `easytodo-grocery:<ref[:12]>` from `deploy/Dockerfile` at `grocery_ref` (a new ref is a new tag, so it rebuilds) and sets the password of role `easytodo`. `utils/bootstrap/portainer.sh` creates or updates the Portainer stack `easytodo-grocery` with the compose file and its env (image, DB password, `GROCERY_SECRET_KEY`, public URL, mail), then runs `create-admin`. The container runs the DB migrations on start.

Releases: in the app repo work reaches `develop` through PRs and `main` only through a release
PR `develop` -> `main` that the operator merges; rulesets enforce both (flow confirmed by the
operator, 2026-10-23). The green CI run on `main` tags the next `vX.Y.Z` with a GitHub release
(job `release` in its `.github/workflows/ci.yml`), so `grocery_ref` can point at a tag commit.
First run: v2.0.1 on `aa8ae8d`, CI run 39962892576, 2026-10-23, still from a direct PR into `main`.
First release from a release PR: v2.0.2 on `512f03f`, CI run 39976242245, 2026-10-23.

`create-admin` creates the admin or makes an existing account admin; it never changes an existing password. `GROCERY_ADMIN_PASSWORD` is therefore only the first password: once the admin changes it in the app, the stored value no longer signs in. Before the exec the bootstrap waits until the container runs `GROCERY_IMAGE` and answers `/healthz`, because the Portainer stack update can return while the old container still answers (DEV deploy 2026-10-21).

Portainer stack `easytodo-grocery`, **bridge**, `8101:8000`, `DB_HOST` = `host.docker.internal`. The public URL is the only origin the app accepts for forms and WebSockets: prod `https://grocery.dkhomelabserver.xyz`, dev `http://192.168.122.50:8101`.

Client address: on prod the app trusts `X-Forwarded-For`/`X-Forwarded-Proto` only from `192.168.50.50` (`environments.prod.public_proxy` in `config/services.yml`), the OPNsense HAProxy. HAProxy backend `grocery` (server `grocery-app`, `192.168.50.30:8101`) sends `option forwardfor` and `X-Forwarded-Proto: https` since 2026-10-21 (`utils/opnsense-grocery-xff.sh`); before that the app saw every public client as the router.

v1 (Flask) ran until 2026-10 with database `todo_grocery` / role `prod_todo_grocery`; the database is left in place. v1 code: tag `legacy-v1` in the app repo; import guide `docs/migration-from-v1.md` there.

Commands on the app host:

```bash
docker logs easytodo-grocery-easytodo-1 2>&1 | grep -E "reset|invite"   # mail links with the console backend
docker exec -it easytodo-grocery-easytodo-1 python -m easytodo.cli --help
```
