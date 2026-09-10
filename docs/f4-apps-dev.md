# F4 — Apps on dev (then prod rollout)

> **Gate:** finish + test on **dev** (`ubuntu-apps-dev` @ `192.168.122.50`).  
> Roll out to **physical prod** only after you sign off tests below.

## What is deployed

Ansible playbook `ansible/playbooks/deploy-core.yml` syncs `compose/core/` (+ grocery compose) to `/opt/homelab/compose/` and runs `docker compose up -d` with profiles `auth,media` by default.

### Port table (DEV `.50`)

| Priority | Service | Port (host) | Status target | Notes |
|----------|---------|-------------|---------------|--------|
| P0 | Portainer | 9000 / 9443 | Up | UI + grocery stack |
| P0 | Postgres 16 | 5432 | Up | Shared core DBs + grocery `todo_grocery` |
| P0 | pgAdmin | 5050 | Up | `admin@example.com` / `POSTGRES_PASSWORD` |
| P0 | Homarr | 7575 | Up | dashboard |
| P0 | Dozzle | 8080 | Up | container logs |
| P0 | Trilium | 8082 | Up | notes |
| P0 | Actual | 5006 | Up | budget |
| P0 | Linkwarden | 3001 | Up | bookmarks |
| P0 | Omni-tools | 8083 | Up | |
| P0 | DumbWhois | 8084 | Up | |
| P0 | BentoPDF | 8085 | Up | |
| P0 | Authelia | **9091** (HTTPS) | Up | profile `auth`; see below |
| P0 | EasyTodo Grocery | 8101 | Up | Portainer stack from `compose/grocery/` (bridge) |
| P1 | Syncthing | 8384 / 22000 | Up | LAN sync UI + sync ports |
| P1 | Navidrome | 4533 | Up | empty `/music` volume on DEV |
| P1 | Jellyfin | 8096 | Up | profile `media`; empty library OK |
| P1 | Immich | 2283 | Up | profile `media`; own Postgres+Redis; **local volumes** (not NFS) |
| P2 | Beszel hub | 8090 | Up | metrics UI |
| P2 | Beszel agent | (host net :45876) | Optional | profile `beszel-agent` + `BESZEL_KEY` after hub setup |
| P2 | Diun | — | Up | image-update watcher; stdout logs |
| P2 | Zotify | 4381 | Up | CLI helper; Spotify OAuth on 4381 during login only |

**Grocery** is not in core compose; use `compose/grocery/docker-compose.yml` via Portainer (synced to `/opt/homelab/compose/grocery`).

### RAM (DEV nested)

Nested Proxmox host has **~8 GiB**. To fit Immich + Jellyfin + the rest:

- `ubuntu-apps-dev` raised to **6144 MiB** (was 4096); TF `environments/dev/terraform.tfvars` matches.
- Disk raised to **27G** (was 16G) on nested `local-lvm` — Immich/Jellyfin images need it; TF `storage_size = 27`.
- CPU set to **`host`** on nested PVE (was `qemu64`) so Immich ML NumPy gets x86-64-v2/SSE4.2.
- `home-assistant-dev` temporarily set to **2048 MiB** on nested PVE to free headroom (not managed by this repo’s TF).
- Compose uses strict `mem_limit` on every service; Immich/Jellyfin behind profile `media`.
- Immich Postgres **768m**, Immich server **1536m**, ML **384m**, pgAdmin **384m** (lower Immich limits OOM’d on DEV).

Laptop libvirt “Proxmox” guest stayed at 8 GiB — do not add more guests without raising that first.

## Deploy (dev)

```bash
export POSTGRES_PASSWORD="$(cat ~/.homelab-postgres-dev-pass)"
export IMMICH_DB_PASSWORD="$(cat ~/.homelab-immich-db-dev-pass)"
export LINKWARDEN_URL=http://192.168.122.50:3001
# Default profiles in playbook: auth,media
# Optional: BESZEL_KEY=… after hub UI setup; ZOTIFY_* unused (interactive login)

cd ansible
ansible-playbook -i environments/dev/hosts.ini playbooks/deploy-core.yml
```

Or push to `homelab-v2` (paths under `compose/` / `ansible/`) with runner label `homelab-dev` online → `apps-deploy-dev.yml`.

### Authelia (DEV)

- URL: `https://192.168.122.50:9091` (self-signed — accept browser warning) or `https://authelia.homelab.local:9091`
- User: `admin`
- Password file: `~/.homelab-authelia-dev-pass` (not in git)
- Config: `compose/core/authelia/` (file users + sqlite); TLS cert generated on deploy under `authelia/certs/`
- Cookie domain `homelab.local` — for SSO cookies add to client `/etc/hosts`:
  `192.168.122.50 authelia.homelab.local homelab.local`
- Disable: `COMPOSE_PROFILES=media` (drop `auth`) before deploy.

### Zotify (DEV)

- No web UI. Volumes hold music + `~/.zotify` credentials after first login.
- OAuth during Spotify login: host port **4381**
- Usage:

  ```bash
  ssh -i ~/.ssh/homelab_dev_ed25519 ubuntu-dev@192.168.122.50
  docker exec -it homelab-core-zotify-1 zotify '<spotify-url>'
  ```

- **Blocker:** needs a Spotify account and interactive browser login (callback to `:4381`). Do not put Spotify secrets in git.

### Portainer first-admin (dev)

- UI: `http://192.168.122.50:9000`
- Password: `~/.homelab-portainer-dev-pass`

### Grocery (Portainer) — bridge + published ports

Upstream grocery Git compose uses `network_mode: host` → Portainer shows **no** Published Ports. DEV uses `compose/grocery/docker-compose.yml`: **bridge** + `8101:8101`, `DB_HOST=host.docker.internal`.

1. DB prep once (`todo_grocery` / role `prod_todo_grocery` — password in `~/.homelab-grocery-db-dev-pass`)
2. Image `easy-todo-grocery-nodb:latest` (built earlier from app repo)
3. Portainer stack `easytodo-grocery` from `/opt/homelab/compose/grocery/docker-compose.yml` (or this repo path `compose/grocery/docker-compose.yml`) with env:

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

4. App: `http://192.168.122.50:8101` — Portainer **Published Ports** `0.0.0.0:8101→8101`

## Test checklist (you)

1. [x] Portainer `:9000`
2. [x] Homarr `:7575` / Dozzle `:8080` / pgAdmin `:5050`
3. [x] Linkwarden `:3001` / Trilium `:8082` / Actual `:5006` / Omni `:8083` / DumbWhois `:8084` / BentoPDF `:8085`
4. [x] Grocery `:8101` with Published Ports visible
5. [x] Authelia `https://192.168.122.50:9091` — `admin` / `~/.homelab-authelia-dev-pass`
6. [x] Syncthing `:8384` / Navidrome `:4533` / Jellyfin `:8096` / Immich `:2283` (+ ML healthy with CPU=host)
7. [x] Beszel hub `:8090` / Diun running / Zotify container Up
8. [ ] Optional: Beszel agent (`COMPOSE_PROFILES=…,beszel-agent` + `BESZEL_KEY` from hub UI)
9. [ ] Optional: Spotify login for Zotify (`docker exec -it … zotify`)

When all OK → prod rollout.

## Prod rollout (physical) — after your OK

Do **not** run this until F3 physical Proxmox `.20.20` is online and TF apply has created `ubuntu-apps` @ `.50.30`.

1. **F3 host up** — `docs/f3-proxmox.md` + `utils/f3-proxmox-preflight.sh`
2. **TF apply prod** — VMs + cloud-init
3. **Secrets** — new `POSTGRES_PASSWORD` / `IMMICH_DB_PASSWORD`; Immich media → NFS SA500 (prod only)
4. **Deploy** — `apps-deploy-prod.yml` or ansible with prod inventory
5. **Grocery** — Portainer on `.50.30` + OPNsense HAProxy
6. Smoke same ports on `.50.30`

Dev and prod share `compose/core` + playbook; inventory, secrets, `LINKWARDEN_URL`, and Immich storage path differ.
