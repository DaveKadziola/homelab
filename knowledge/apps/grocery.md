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

Portainer stack `easytodo-grocery`, **bridge**, `8101:8000`, `DB_HOST` = `host.docker.internal`. The public URL is the only origin the app accepts for forms and WebSockets: prod `https://grocery.dkhomelabserver.xyz`, dev `http://192.168.122.50:8101`.

Client address: on prod the app trusts `X-Forwarded-For`/`X-Forwarded-Proto` only from `192.168.50.50` (`environments.prod.public_proxy` in `config/services.yml`), the OPNsense HAProxy. HAProxy backend `grocery` (server `grocery-app`, `192.168.50.30:8101`) sends `option forwardfor` and `X-Forwarded-Proto: https` since 2026-10-21 (`utils/f2-opnsense-grocery-xff.sh`); before that the app saw every public client as the router.

v1 (Flask) ran until 2026-10 with database `todo_grocery` / role `prod_todo_grocery`; the database is left in place. v1 code: tag `legacy-v1` in the app repo; import guide `docs/migration-from-v1.md` there.

Commands on the app host:

```bash
docker logs easytodo-grocery-easytodo-1 2>&1 | grep -E "reset|invite"   # mail links with the console backend
docker exec -it easytodo-grocery-easytodo-1 python -m easytodo.cli --help
```
