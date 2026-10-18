# Repository audit — 2026-09-10 (F9-F2)

**Question:** can someone who did not build this lab operate and rebuild it from git alone?

**Also:** a fresh-eyes pass (separate agent, no chat context) walked README → `docs/kb/` → compose/terraform/ansible. Findings below are from the tree on `homelab-v2` plus that pass.

`./utils/run-tests.sh --env dev --suite config` → **PASS=64 FAIL=0** (compose ports match `services.yml` and `docs/f4-apps-dev.md`).

---

## First 30 minutes (stranger)

1. Open `README.md` — two environments, mermaid, “start at `docs/kb/`”. Good.
2. Open `docs/kb/rebuild.md` — order is clear; F5 restore is explicitly missing.
3. Tripwires:
   - README **Quick start — dev** still says “Register runner → nested PVE → push” and does not say “secrets live in `~/.homelab-secrets/dev` *and* Bitwarden *and* GH, and GH cannot give them back”.
   - `docs/manual-setup.md` is a long F0 checklist (done dates in 2026-06). A stranger will treat it as current procedure.
   - `utils/create-dev-vm.sh` is deprecated but still executable and still targets `192.168.122.50` — same IP as the TF guest.
   - `ansible/docker-containers.yml` looks like *the* app inventory (NPM, `admin`/`admin` pgAdmin). It is dead code.

**Verdict:** a careful reader can deploy **empty** DEV apps if they already have nested PVE + GH secrets + the SSH key. They cannot restore data. They will improvise on grocery (Portainer), Zotify, Homarr, Syncthing peers, and Bitwarden.

---

## Findings

### R1 — Dead Ansible inventory with default password

| | |
|--|--|
| Severity | **high** |
| Path | `ansible/docker-containers.yml`, `ansible/user-setup.yml` |
| Rec | Delete after confirming nothing references them, or move to `ansible/legacy/`. Header marked DEPRECATED in this change. |

### R2 — Deprecated libvirt VM script still present

| | |
|--|--|
| Severity | **medium** |
| Path | `utils/create-dev-vm.sh` |
| Rec | Keep the deprecation banner; add `exit 1` unless `HOMELAB_I_MEAN_IT=1`, or delete. Running it would fight `ubuntu-apps-dev`. |

### R3 — Port / IP duplication is improved, not gone

| | |
|--|--|
| Severity | **low** |
| Path | `config/services.yml` (source of truth) · `compose/core/docker-compose.yml` · `docs/f4-apps-dev.md` · `docs/kb/operations.md` · `docs/kb/apps/*.md` · `terraform/environments/*/terraform.tfvars` · leftover `ansible/docker-containers.yml` |
| Evidence | config suite proves f4 + compose agree. KB login table still copies URLs by hand. |
| Rec | KB should say “ports from `services.yml`” and only special-case Authelia. Do not edit `docker-containers.yml`. |

### R4 — CI does not match F7 deploy

| | |
|--|--|
| Severity | **high** |
| Path | `.github/workflows/apps-deploy-dev.yml`, `apps-deploy-prod.yml`, `ci-validate.yml` |
| Evidence | Deploy jobs pass only `POSTGRES_PASSWORD`. Playbook requires the full identity set. No `tests-dev.yml` in the tree (README still mentioned it earlier; it is gone or was never committed). Prod has `post-deploy-tests`; DEV does not. |
| Rec | Inject every GH Environment secret. Add `tests-dev.yml` after `apps-deploy-dev`. Fix `docker compose config` placeholders. Patched in this F9 change except the missing DEV tests workflow (still recommended). |

### R5 — Two secret generators

| | |
|--|--|
| Severity | **medium** |
| Path | `utils/gen-app-credentials.sh` (current) vs `utils/bootstrap-f1-secrets.sh` + `utils/export-secrets-for-bitwarden.sh` (F1, infra-only names) |
| Rec | README should name **one** entry: `gen-app-credentials.sh`. Point F1 scripts at “infra leftovers only”. |

### R6 — Bitwarden is mandatory in docs, optional in practice

| | |
|--|--|
| Severity | **high** (DR) |
| Path | `docs/secrets-inventory.md`, `docs/kb/security.md` |
| Evidence | No `bw` CLI. No leftover staging file. Inventory F7 rows were appended as raw markdown after the “last updated” line (broken table). |
| Rec | Export from `~/.homelab-secrets/dev`. Fix the inventory table. Until then a laptop loss loses app passwords. |

### R7 — README vs KB vs f4

| | |
|--|--|
| Severity | **medium** |
| Path | `README.md` roadmap still mixed F1–F10; `docs/f4-apps-dev.md` is a living DEV diary; `docs/kb/` is the operator entry |
| Rec | README: keep architecture + links. Move checklists into KB. Mark `f4-apps-dev.md` “historical DEV bring-up”. |

### R8 — Naming

| | |
|--|--|
| Severity | **low** |
| Examples | guest `ubuntu-apps` vs docs `ubuntu-apps-dev`; inventory group `ubuntu_docker`; Homarr image `homarr-labs` vs leftover `ajnart/homarr`; grocery role `prod_todo_grocery` on DEV |
| Rec | One sentence in `architecture.md` (already: TF name + env suffix). Rename grocery role when touching that DB. |

### R9 — Secrets hygiene in git

| | |
|--|--|
| Severity | **low** (git) / see S9 for disk |
| Evidence | Authelia users file = argon2 hash (OK). `.gitignore` covers `.env`, tfstate, `opnsense/backups/`. gitleaks on the **git** tree (without working-tree backups) should be clean. `ansible/docker-containers.yml` literal `admin` is a default, not a live secret. |
| Rec | Add `.gitleaks.toml` + a CI `gitleaks detect` step. |

### R10 — Config still outside IaC

| | |
|--|--|
| Severity | **high** for prod rebuild |
| Missing | SA500/Purple disks (A1), NFS exports, backup jobs, HAProxy/ACME, Authelia in front of apps, Homarr/Trilium/Actual first-run, Zotify OAuth, Syncthing peers, runner `svc.sh` sudo |
| Rec | These are F5 / F3 metal / F9-F3 gaps, not drive-by refactors. |

### R11 — Tests are good; CI barely uses them

| | |
|--|--|
| Severity | **medium** |
| Path | `tests/` + `utils/run-tests.sh` vs workflows |
| Rec | DEV workflow after deploy. Document `SKIP` for prod-only net checks (already in `tests/README.md`). |

### R12 — Understandability score

| Audience | Can they… | |
|----------|-----------|--|
| Operator with Bitwarden + this laptop | Daily logins, redeploy DEV | **yes** — `docs/kb/operations.md` |
| Stranger with only GitHub clone | Rebuild DEV empty | **maybe** — after nested PVE tribal steps |
| Stranger after laptop death, no Bitwarden | Recover passwords | **no** |
| Anyone | Rebuild prod with media | **no** — F5 |

---

## Leftover / confusing files (checklist)

| File | Action |
|------|--------|
| `utils/create-dev-vm.sh` | deprecate hard or delete |
| `ansible/docker-containers.yml` | delete / legacy/ |
| `ansible/user-setup.yml` | same (cloud-init + deploy-core superseded it) |
| `docs/manual-setup.md` | archive as F0 |
| `utils/bootstrap-f1-secrets.sh` | infra-only; don’t run `--all` over F7 |
| `opnsense/backups/*.xml` | not in git; shred after Bitwarden |
| `ansible/hosts.ini` | leftover; `.219` labelled as Docker host |
| `utils/start_qemu_default_net` | undocumented one-liner |
| `utils/reset-nested-proxmox-root.sh` | hardcoded `/home/kdzl/HomeLab/VMs/Proxmox.qcow2` |
| `docs/opnsense-ui-walkthrough.md` | **SUPERSEDED** — wrong APP / PVE IPs |

---

## Fresh-eyes addendum

A second reader (no chat context) walked README → KB → compose. Same verdict: **cannot rebuild DEV from `rebuild.md` alone.** Extra findings folded in here; dangerous docs were stamped or corrected in the same change.

| Sev | Finding | Follow-up |
|-----|---------|-----------|
| high | README mermaid still showed `homelab-dev VM libvirt` as the apps host | Redrawn: `Proxmox` → `ubuntu-apps-dev`; prod runner on apps VM |
| high | README roadmap said “F1 current” | Roadmap now F1–F8 done, F9 gate FAIL, F5/F3 metal open |
| high | `docs/opnsense-ui-walkthrough.md` APP `/24` and PVE `.20.10` (printer) | Banner: superseded; use `network.md` |
| high | `collect-homelab-macs.sh` defaulted to `.20.10` | Default is now `.20.20` |
| high | Nested PVE hypervisor is assumed, not created | Stated in `rebuild.md` and `dev-proxmox.md` |
| high | Grocery image + `todo_grocery` are not in this repo’s init | `postgres.md` and `rebuild.md` no longer claim they are |
| high | APP CIDR written as `.50.50/26` / `.50.48/26` / guest `.50.30/26` | Still **open** — do not invent a fourth number; fix in F3 metal |
| high | Three Proxmox token IDs in docs/scripts | Still **open** — pick one name at F3 |
| med | `docs/manual-setup.md` is a second front door | README Prerequisites now point at `rebuild.md` |
| med | “greenfield plan” is not in the repo | Cursor plan only; do not cite it as a file |
| med | Hardcoded `192.168.122.50` in compose/workflows/docs | Still **open** — `services.yml` `environments.dev.host` |
| med | Firefly/Grafana DBs in `postgres-init`, no such apps | Honest in `postgres.md`; trim init later |

**Operate existing DEV from the KB:** yes, if the SSH key and `~/.homelab-secrets/dev/` already exist. That is not a clean-room rebuild.
