# F4 — Apps on dev (then prod rollout)

> **Gate:** finish + test on **dev** (`ubuntu-apps-dev` @ `192.168.122.50`).  
> Roll out to **physical prod** only after you sign off tests below.

## What is deployed

Ansible playbook `ansible/playbooks/deploy-core.yml` syncs `compose/core/` to `/opt/homelab/compose/core` and runs `docker compose up -d`.

| Service | Port (host) | Notes |
|---------|-------------|--------|
| Portainer | 9000 / 9443 | UI + Git stacks (grocery) |
| Postgres 16 | 5432 | Core DBs + grocery `todo_grocery` (Portainer stack) |
| pgAdmin | 5050 | login `admin@example.com` / `POSTGRES_PASSWORD` |
| Homarr | 7575 | dashboard |
| Dozzle | 8080 | container logs |
| Trilium | 8082 | notes |
| Actual | 5006 | budget |
| Linkwarden | 3001 | bookmarks |
| Omni-tools | 8083 | |
| DumbWhois | 8084 | |
| BentoPDF | 8085 | |
| Authelia | 9091 (HTTPS) | profile `auth` — enabled by default on deploy (`COMPOSE_PROFILES=auth`) |
| Zotify | 4381 | Spotify downloader helper (CLI via `docker exec`; OAuth on 4381) |
| EasyTodo Grocery | 8101 | Portainer stack from `compose/grocery/` (bridge + published ports) |

**Grocery** is not in core compose; use `compose/grocery/docker-compose.yml` (synced to `/opt/homelab/compose/grocery`) via Portainer. See **Grocery** below.

## Deploy (dev)

```bash
# Password lives in ~/.homelab-postgres-dev-pass and GH env secret POSTGRES_PASSWORD (dev)
export POSTGRES_PASSWORD="$(cat ~/.homelab-postgres-dev-pass)"
export LINKWARDEN_URL=http://192.168.122.50:3001
# Optional: export COMPOSE_PROFILES=auth  (default in deploy-core.yml)
# Optional: export ZOTIFY_USERNAME=… ZOTIFY_TOKEN=…  (usually unused — interactive login)

cd ansible
ansible-playbook -i environments/dev/hosts.ini playbooks/deploy-core.yml
```

Or push to `homelab-v2` (paths under `compose/` / `ansible/`) with runner label `homelab-dev` online → `apps-deploy-dev.yml`.

### Authelia (DEV)

- UI: `https://192.168.122.50:9091` (self-signed TLS — accept browser warning) or `https://authelia.homelab.local:9091`
- User: `admin`
- Password: `~/.homelab-authelia-dev-pass` (not in git)
- Config: `compose/core/authelia/` (file users + sqlite notifier); TLS cert generated on deploy under `authelia/certs/`
- Cookie domain is `homelab.local`. For a working login session/SSO, add to client `/etc/hosts`:
  `192.168.122.50 authelia.homelab.local homelab.local`
- Disable: set `COMPOSE_PROFILES=` (empty) before deploy, or stop the `authelia` service on the host.

### Zotify (DEV)

- Helper container in core compose (no web UI). Music/podcast volumes + config volume persist credentials after first login.
- OAuth port during Spotify login: `http://192.168.122.50:4381`
- Use:

  ```bash
  ssh ubuntu-dev@192.168.122.50
  docker exec -it homelab-core-zotify-1 zotify -u '<spotify-username>' '<track-or-playlist-url>'
  ```

- Optional env placeholders: `ZOTIFY_USERNAME` / `ZOTIFY_TOKEN` in `.env` (upstream prefers interactive login + `credentials.json` in the volume).

### Portainer first-admin (dev)

Portainer CE 2.45+ prints a one-time `setup_token` in `docker logs` on startup. Create admin before the security timeout (or `docker restart` Portainer if you see the timeout message).

- UI: `http://192.168.122.50:9000` — paste setup token + set admin password
- Password for this lab: `~/.homelab-portainer-dev-pass` (not in git)
- After admin exists, add environment **local** (Docker socket) if the Environments list is empty

### Grocery (Portainer) — bridge + published ports on `.50`

Upstream `easytodo-grocery-list` compose uses `network_mode: host`, so Portainer shows **no** Published Ports. DEV uses `compose/grocery/docker-compose.yml` instead: **bridge** + `8101:8101`, `DB_HOST=host.docker.internal` (Postgres published on the host). Same app URL.

1. **DB prep** (once, against `homelab-core-postgres-1`):
   - `CREATE DATABASE todo_grocery;`
   - role `prod_todo_grocery` with password (store in `~/.homelab-grocery-db-dev-pass`)
   - apply repo DDL `ddl/3_3-ddl_prod.sql` with owner `postgres` remapped to `homelab`
2. **Image** — build once from the app repo if missing: `easy-todo-grocery-nodb:latest` (Portainer Git build from `DaveKadziola/easytodo-grocery-list` or local Dockerfile).
3. **Portainer → Stacks** (preferred for Published Ports visibility):
   - Name: `easytodo-grocery`
   - Method: **Web editor** / file — paste or load `/opt/homelab/compose/grocery/docker-compose.yml` (synced by `deploy-core.yml`)
   - Or Repository: this `homelab` repo, compose path `compose/grocery/docker-compose.yml`
   - Env:

     | Name | Value |
     |------|--------|
     | `DB_HOST` | `host.docker.internal` |
     | `DB_PORT` | `5432` |
     | `DB_NAME` | `todo_grocery` |
     | `DB_USER` | `prod_todo_grocery` |
     | `DB_PASSWORD` | (from `~/.homelab-grocery-db-dev-pass`) |
     | `DB_SCHEMA` | `prod` |
     | `APP_HOST_NAME` | `0.0.0.0` |
     | `APP_HOST_PORT` | `8101` |
     | `SOCKETIO_HOST` | `192.168.122.50` |
     | `SOCKETIO_PORT` | `8101` |

4. Container: `easytodo-grocery-easytodo-1` — Portainer should list **Published Ports** `8101:8101`.
5. App: `http://192.168.122.50:8101`

**Do not** use upstream `docker/v1.0.0/no-db/docker-compose.yml` on DEV if you need Portainer port visibility (host networking hides ports).

## Test checklist (you)

From laptop (libvirt network):

1. [x] `http://192.168.122.50:9000` — Portainer (admin set; restart if security timeout)
2. [x] `http://192.168.122.50:7575` — Homarr
3. [x] `http://192.168.122.50:8080` — Dozzle shows containers
4. [x] `http://192.168.122.50:5050` — pgAdmin → server `postgres` / user `homelab`
5. [x] Linkwarden `:3001` / Trilium `:8082` / Actual `:5006` / Omni-tools `:8083` / DumbWhois `:8084` / BentoPDF `:8085`
6. [x] Portainer stack `easytodo-grocery` → `http://192.168.122.50:8101` (Published Ports visible)
7. [ ] Authelia `https://192.168.122.50:9091` — login `admin` / `~/.homelab-authelia-dev-pass` (self-signed)
8. [ ] Zotify container up; optional login via `docker exec` (needs Spotify account)

When all OK → prod rollout.

## Prod rollout (physical) — after your OK

Do **not** run this until F3 physical Proxmox `.20.20` is online and TF apply has created `ubuntu-apps` @ `.50.30`.

1. **F3 host up** — `docs/f3-proxmox.md` + `utils/f3-proxmox-preflight.sh`
2. **TF apply prod** (TFC workspace `homelab` / `infra-apply-prod`) — VMs + cloud-init
3. **DHCP/static** — APP QinQ; confirm SSH to `ubuntu-apps`
4. **Secrets (prod env)** — `POSTGRES_PASSWORD` (new strong value), Proxmox tokens already in place
5. **Runner `homelab-prod`** on a host that can reach `.50.30`
6. **Deploy** — `apps-deploy-prod.yml` (manual / push `main`) or:
   ```bash
   export POSTGRES_PASSWORD=…   # prod secret
   export LINKWARDEN_URL=http://192.168.50.30:3001
   ansible-playbook -i environments/prod/hosts.ini playbooks/deploy-core.yml
   ```
7. **Grocery public path** — Portainer Git on `.50.30` + existing OPNsense HAProxy → backend `.50.30` (not nested IPs)
8. **Smoke** same ports on `.50.30`; grocery via public DNS

Dev and prod use the **same** `compose/core` + playbook; only inventory, secrets, and `LINKWARDEN_URL` differ.
