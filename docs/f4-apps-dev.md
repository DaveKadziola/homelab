# F4 — Apps on dev (then prod rollout)

> **Gate:** finish + test on **dev** (`ubuntu-apps-dev` @ `192.168.122.50`).  
> Roll out to **physical prod** only after you sign off tests below.

## What is deployed

Ansible playbook `ansible/playbooks/deploy-core.yml` syncs `compose/core/` to `/opt/homelab/compose/core` and runs `docker compose up -d`.

| Service | Port (host) | Notes |
|---------|-------------|--------|
| Portainer | 9000 / 9443 | UI + Git stacks (grocery) |
| Postgres 16 | 5432 | DBs: linkwarden, firefly3, actual, trilium, grafana, easytodo |
| pgAdmin | 5050 | login `admin@example.com` / `POSTGRES_PASSWORD` |
| Homarr | 7575 | dashboard |
| Dozzle | 8080 | container logs |
| Trilium | 8082 | notes |
| Actual | 5006 | budget |
| Linkwarden | 3001 | bookmarks |
| Omni-tools | 8083 | |
| DumbWhois | 8084 | |
| BentoPDF | 8085 | |
| Authelia | 9091 | profile `auth` — off by default |

**Out of this compose:** public grocery (`easytodo-grocery-list`) — deploy via Portainer Git after Portainer is up. See `docs/apps-sources.md`.

## Deploy (dev)

```bash
# Password lives in ~/.homelab-postgres-dev-pass and GH env secret POSTGRES_PASSWORD (dev)
export POSTGRES_PASSWORD="$(cat ~/.homelab-postgres-dev-pass)"
export LINKWARDEN_URL=http://192.168.122.50:3001

cd ansible
ansible-playbook -i environments/dev/hosts.ini playbooks/deploy-core.yml
```

Or push to `homelab-v2` (paths under `compose/` / `ansible/`) with runner label `homelab-dev` online → `apps-deploy-dev.yml`.

## Test checklist (you)

From laptop (libvirt network):

1. [ ] `http://192.168.122.50:9000` — Portainer first-admin setup
2. [ ] `http://192.168.122.50:7575` — Homarr
3. [ ] `http://192.168.122.50:8080` — Dozzle shows containers
4. [ ] `http://192.168.122.50:5050` — pgAdmin → server `postgres` / user `homelab`
5. [ ] Linkwarden / Trilium / Actual / tools URLs respond
6. [ ] Optional: Portainer → Stacks → Git → grocery repo (no NPM/HAProxy on nested LAN)
7. [ ] Optional: `docker compose --profile auth up -d` only after Authelia config under `compose/core/authelia/`

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
