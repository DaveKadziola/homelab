# Homelab v2 (greenfield)

Self-hosted homelab on Proxmox: Terraform + Ansible + Docker Compose, deployed via **GitHub Actions** with dual self-hosted runners.

| Branch | Environment | Effect |
|--------|-------------|--------|
| `homelab-v2` | **dev** | CI validate + deploy to dev VM (laptop libvirt) |
| `main` | **prod** | Terraform apply + app deploy on Proxmox (approval required) |

Legacy pre-v2 code is tagged `legacy-pre-v2` on `main` before merge (see greenfield plan).

## Knowledge base

Operator docs live under **[`knowledge/`](knowledge/)** — start there, do not duplicate them here.

| Topic | Page |
|-------|------|
| How it fits together | [architecture](knowledge/architecture.md) · [infrastructure](knowledge/infrastructure.md) · [networking](knowledge/networking.md) |
| Run / deploy / login | [operations](knowledge/operations.md) · [deployment](knowledge/deployment.md) |
| Clean-room rebuild | [rebuild](knowledge/rebuild.md) · [dr](knowledge/dr.md) · [backup](knowledge/backup.md) |
| Failures we already paid for | [lessons-learned](knowledge/lessons-learned.md) · [troubleshooting](knowledge/troubleshooting.md) |
| F9 audits (2026-09-10) | [security](knowledge/security-audit-2026-09-10.md) · [repo](knowledge/repo-audit-2026-09-10.md) · [rebuild drill](knowledge/rebuild-drill-2026-09-10.md) |
| Per app | [knowledge/apps/](knowledge/apps/) |

## Architecture

```mermaid
flowchart TB
  subgraph laptop [Laptop dev]
    RunnerDev[homelab-dev runner]
    NestedPVE[libvirt VM Proxmox]
    AppsDev[ubuntu-apps-dev 192.168.122.50]
    RunnerDev --> NestedPVE
    NestedPVE --> AppsDev
  end
  subgraph prod [Physical Proxmox]
    PVE[proxmox 192.168.20.20]
    AppsVM[ubuntu-apps 192.168.50.30]
    NASVM[ubuntu-nas 192.168.20.12]
    RunnerProd[ci-runner LXC 192.168.20.14 - homelab-prod runner]
    PVE --> AppsVM
    PVE --> NASVM
    PVE --> RunnerProd
  end
  OPNsense[OPNsense router]
  HA[Home Assistant T620]
  GitHub[GitHub Actions]
  GitHub --> RunnerDev
  GitHub --> RunnerProd
  OPNsense --> prod
```

## Repository layout

```
homelab/
  .github/workflows/     # CI/CD (self-hosted runners)
  ansible/               # VM configuration
  compose/core/          # Core Docker stack (Postgres, …)
  docs/                  # Manual setup, secrets names, app sources
  knowledge/             # Operator knowledge base (F8) — start here
  opnsense/              # Router baseline (F2)
  homeassistant/         # HA config (F5)
  terraform/             # Proxmox VMs (TFC workspace homelab)
  utils/                 # Runner bootstrap, dev VM, secrets helper
```

## Prerequisites

First laptop / rebuild: [`knowledge/rebuild.md`](knowledge/rebuild.md) and [`docs/dev-proxmox.md`](docs/dev-proxmox.md). F0 sprint notes are historical: [`docs/manual-setup.md`](docs/manual-setup.md).

Tools: `git`, `gh`, `terraform`, `ansible`, `ansible-lint`, `docker`, `virsh`, `virt-install`, `openssl`.

## Secrets

Generate locally → **Bitwarden** `homelab/<NAME>/<env>` → `gh secret set`. Names only: [`docs/secrets-inventory.md`](docs/secrets-inventory.md).

App secrets: `utils/gen-app-credentials.sh` (not the older F1 `bootstrap-f1-secrets.sh`).

New values straight into Bitwarden + GitHub + laptop cache, no staging file: `utils/rotate-secrets.py --env prod --generate` (dry run), then `--apply` with Bitwarden unlocked (`export BW_SESSION="$(bw unlock --raw)"`). Existing cache values into Bitwarden only: `--vault-from-cache`.

Scripts that create a secret store it in Bitwarden in the same run through `utils/bw-store.py`; while the vault is locked the names (never the values) are queued, flush with `utils/bw-store.py --pending` after unlocking. Whole cache: `utils/bw-store.py --env all --dry-run`, then without `--dry-run`.

Laptop cache → GitHub Environment: `utils/sync-secrets-to-github.py --env dev` (dry run, names only), then `--apply`. Never pass `--body -` to `gh secret set`: it stores the literal `-`.

## Quick start — dev

1. Register dev runner: `utils/setup-github-runner.sh --label homelab-dev`
2. Nested Proxmox: [`docs/dev-proxmox.md`](docs/dev-proxmox.md) — `ensure-dev-proxmox.sh` + `bootstrap-dev-proxmox.sh`
3. PR to `homelab-v2` → `infra-plan-dev.yml`; push (merge) → `infra-apply-dev.yml` (Terraform IaC, state in HCP workspace `homelab-dev`)
4. Apps: `apps-deploy-dev.yml` → `ubuntu-apps-dev` @ `192.168.122.50`

## Quick start — prod

Order (after F2–F3): OPNsense → Proxmox TF apply → Ansible → Compose. Prod workflows require:

- Self-hosted runner `homelab-prod` in the LXC container `ci-runner` (CT 110, `192.168.20.14`) on the Proxmox host: `utils/pve-ci-runner-lxc.sh`
- TFC workspace `homelab` execution mode **Local**
- GitHub Environment **prod** approval on `main`

## CI/CD workflows

| Workflow | Trigger | Runner |
|----------|---------|--------|
| `ci-validate.yml` | push/PR `homelab-v2` | `homelab-dev` |
| `infra-plan-dev.yml` | PR → `homelab-v2` / manual | `homelab-dev` |
| `infra-apply-dev.yml` | push `homelab-v2` / manual | `homelab-dev` |
| `apps-deploy-dev.yml` | push `homelab-v2` | `homelab-dev` |
| `infra-plan.yml` | PR → `main` | `homelab-prod` |
| `infra-apply-prod.yml` | push `main` | `homelab-prod` |
| `apps-deploy-prod.yml` | after `infra-apply-prod` / manual | `homelab-prod` |
| `tests-dev.yml` | push `homelab-v2` (tests, config) / manual; after a deploy: job in `apps-deploy-dev.yml` | `homelab-dev` |

Bootstrap: [`utils/setup-github-runner.sh`](utils/setup-github-runner.sh); the prod runner container: [`utils/pve-ci-runner-lxc.sh`](utils/pve-ci-runner-lxc.sh)

## Applications

P0/P1/P2 phases and sources: [`docs/apps-sources.md`](docs/apps-sources.md). Public app: `grocery.dkhomelabserver.xyz`.

Service endpoints (port, health path, expected status, container, priority) are declared once in [`config/services.yml`](config/services.yml); accounts and secret names in [`config/identities.yml`](config/identities.yml).

## Tests

```bash
utils/run-tests.sh --env dev --suite all
```

Suites (`smoke`, `infra`, `net`, `config`, `storage`) are driven by `config/services.yml` (`storage` by `config/storage.yml`) — see [`tests/README.md`](tests/README.md). `SKIP` is not a failure, so the same command works while prod is still being built. F5 restore (`--suite restore`) is opt-in and not part of `--suite all`.

## Network

Prod Proxmox **`192.168.20.20`**; slots/VLANs: [docs/network.md](docs/network.md). Dev libvirt: `192.168.122.x`.  
WireGuard: [docs/wireguard.md](docs/wireguard.md). OPNsense F2: [docs/opnsense-baseline.md](docs/opnsense-baseline.md).

## Roadmap

| Phase | Scope |
|-------|--------|
| **F1–F8** | Done on `homelab-v2` (repo, DEV nested PVE, apps, identities, tests, KB) |
| **F9** | Audits written 2026-09-10 — **merge to `main` still FAIL** ([rebuild drill](knowledge/rebuild-drill-2026-09-10.md)) |
| **F5** | NAS / NFS / Samba / backups — DEV loopback + Samba + timer + restore and storage suites ([f5-storage](docs/f5-storage.md)). Prod disks identified and configured (SA500 media, Purple backups + share), attach + one-time format not run yet; rclone / HAOS / vzdump still blocked on metal |
| **F3 metal / prod** | Physical Proxmox apply — not started |
| **F10** | Monitoring / alerts — after prod |

## Operations

See [`knowledge/operations.md`](knowledge/operations.md). Short version:

- Add an app: `config/services.yml` first, then compose, then `knowledge/apps/<app>.md`
- Rotate a secret: `utils/gen-app-credentials.sh` (stores Bitwarden itself) → bootstrap
- Logs: Dozzle `:8080`
- Logins: `~/.homelab-secrets/<env>/` — never the legacy `~/.homelab-*-dev-pass` files

## License

See [LICENSE](LICENSE).
