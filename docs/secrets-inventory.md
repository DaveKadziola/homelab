# Secrets inventory — homelab v2

> **Status:** name template (F0-10) — **no values**.  
> **Procedure:** generate locally → Bitwarden `homelab/<NAME>/<env>` → `gh secret set` / `gh variable set`.  
> **Related:** [manual-setup.md](manual-setup.md) (F0/F1), greenfield v2 plan.

**Rule:** GitHub Secrets are **write-only** — after `gh secret set` you cannot read values back from GH. A copy in Bitwarden is mandatory.

Helper scripts:

| Script | Purpose |
|--------|---------|
| `utils/export-secrets-for-bitwarden.sh` | Legacy F1 text export (`--regenerate` for GH-only secrets) |
| `utils/bw-store.py` | Store `~/.homelab-secrets/<env>/<NAME>` as Bitwarden `homelab/<NAME>/<env>`. `gen-app-credentials.sh`, `setup-rclone-pcloud.sh` and `bootstrap-f3-proxmox.sh --set-token` call it for every new value; with the vault locked the names wait in `~/.homelab-secrets/.bw-pending` until `--pending`. `--env dev\|prod\|prod-plan\|all` stores a whole cache (`sync-cache-to-bitwarden.sh` is now a wrapper for it) |
| `utils/setup-rclone-pcloud.sh` | After OAuth: pCloud folders, optional `RCLONE_CONFIG` in GH prod |
| `utils/bootstrap-f1-secrets.sh` | Push secrets/variables to GitHub (values not printed) |
| `utils/sync-secrets-to-github.py` | Push `~/.homelab-secrets/<env>/` to a GitHub Environment (dry run unless `--apply`); `UBUNTU_DOCKER_PASSWORD` goes as its SHA-512 crypt hash, `RCLONE_CONFIG` (prod) as base64 |


## Legend

| Column | Meaning |
|--------|---------|
| **GH env** | `dev` \| `dev-plan` (PR plan only, [dev-proxmox.md](dev-proxmox.md) "PR plan") \| `prod` \| `prod-plan` (PR plan only, [f3-proxmox.md](f3-proxmox.md) "PR plan") \| `prod-gate` (owner approval for a risky plan, holds no secrets) \| `repo` \| — (not in GH) |
| **Type** | `secret` \| `variable` |
| **Status** | `planned` \| `set` \| `N/A` |
| **Bitwarden** | path in Password Manager |

---

## GitHub Environments — secrets

| Name | GH env | Type | Bitwarden | Status | Notes |
|------|--------|------|-----------|--------|-------|
| `POSTGRES_PASSWORD` | dev | secret | `homelab/POSTGRES_PASSWORD/dev` | set | F1 2026-06-29 |
| `POSTGRES_PASSWORD` | prod | secret | `homelab/POSTGRES_PASSWORD/prod` | set | F1 2026-06-29; rotated 2026-10-18 |
| `PROXMOX_API_TOKEN_SECRET` | dev | secret | `homelab/PROXMOX_API_TOKEN_SECRET/dev` | set | placeholder — update at F3 |
| `PROXMOX_API_TOKEN_SECRET` | prod | secret | `homelab/PROXMOX_API_TOKEN_SECRET/prod` | set | placeholder — update at F3 |
| `PROXMOX_API_TOKEN_SECRET` | prod-plan | secret | `homelab/PROXMOX_API_TOKEN_SECRET/prod-plan` | set | read-only token `homelab-prod@pam!plan` (`PVEAuditor`); `~/.homelab-secrets/prod-plan/` |
| `PROXMOX_API_TOKEN_SECRET` | dev-plan | secret | `homelab/PROXMOX_API_TOKEN_SECRET/dev-plan` | set | read-only token `root@pam!plan` on the nested DEV PVE (`PVEAuditor`); `~/.homelab-secrets/dev-plan/` |
| `TF_API_TOKEN`, `UBUNTU_DOCKER_PASSWORD` | dev-plan | secret | as in dev | set | `UBUNTU_DOCKER_PASSWORD`: the same SHA-512 hash as dev, or the plan shows the snippet as changed |
| `PROXMOX_API_TOKEN_ID`, `PROXMOX_API_URL`, `PROXMOX_SSH_USERNAME`, `UBUNTU_DOCKER_SSH_PUB` | dev-plan | variable | — | set | `root@pam!plan`; the rest copied from dev |
| `PROXMOX_SSH_PASSWORD` | dev | secret | `homelab/PROXMOX_SSH_PASSWORD/dev` | set | placeholder |
| `PROXMOX_SSH_PASSWORD` | prod | secret | `homelab/PROXMOX_SSH_PASSWORD/prod` | set | placeholder |
| `UBUNTU_DOCKER_PASSWORD` | dev | secret | `homelab/UBUNTU_DOCKER_PASSWORD/dev` | set | F1 |
| `UBUNTU_DOCKER_PASSWORD` | prod | secret | `homelab/UBUNTU_DOCKER_PASSWORD/prod` | set 2026-10-19 | SHA-512 hash in GH; plain text in `~/.homelab-secrets/prod/UBUNTU_DOCKER_PASSWORD` + Bitwarden |
| `UBUNTU_DOCKER_PASSWORD` | prod-plan | secret | `homelab/UBUNTU_DOCKER_PASSWORD/prod` | set | the same SHA-512 hash as prod, or the plan shows the snippet as changed |
| `UBUNTU_DOCKER_SSH_PRIV` | dev | secret | `homelab/UBUNTU_DOCKER_SSH_PRIV/dev` | set | `~/.ssh/homelab_dev_ed25519`. Cache copy queued for Bitwarden 2026-10-22. |
| `UBUNTU_DOCKER_SSH_PRIV` | prod | secret | `homelab/UBUNTU_DOCKER_SSH_PRIV/prod` | set 2026-10-19 | `~/.ssh/homelab_prod_ed25519` (own prod key, `homelab-prod`); the prod deploy installs it on the runner. Cache copy queued for Bitwarden 2026-10-22. |
| `TF_API_TOKEN` | prod | secret | `homelab/TF_API_TOKEN/prod` | set | F1 |
| `TF_API_TOKEN` | prod-plan | secret | `homelab/TF_API_TOKEN/prod` | set | HCP token with access to workspace `homelab` |
| `SSL_CERT` | prod | secret | `homelab/SSL_CERT/prod` | planned | optional; legacy backup |
| `SSL_CHAIN` | prod | secret | `homelab/SSL_CHAIN/prod` | planned | optional |
| `SSL_PKEY` | prod | secret | `homelab/SSL_PKEY/prod` | planned | optional |
| `RCLONE_CONFIG` | prod | secret | `homelab/RCLONE_CONFIG/prod` | set | generated 2026-09-11 — `rclone.conf` in GH prod; copy to Bitwarden via cache |
| `HA_TOKEN` | prod | secret | `homelab/HA_TOKEN/prod` | set 2026-10-21 | long-lived token the owner creates in the HA profile; `utils/ha.py` (deploy, backup pull, tests) |
| `HA_TOKEN` | dev | secret | `homelab/HA_TOKEN/dev` | set 2026-10-20 | made by `utils/ha.py --env dev bootstrap` on the HAOS twin |
| `HA_ADMIN_PASSWORD` | dev | secret | `homelab/HA_ADMIN_PASSWORD/dev` | set 2026-10-20 | owner account `admin` of the DEV twin (onboarding) |
| `HA_SSH_PRIV` | dev, prod | secret | `homelab/HA_SSH_PRIV/<env>` | set 2026-10-20 | ed25519 key of the Terminal & SSH add-on; public half derived |
| `HA_BACKUP_PASSWORD` | dev, prod | secret | `homelab/HA_BACKUP_PASSWORD/<env>` | set 2026-10-20 | password of the Supervisor backups the NAS pulls; needed to restore |
| `KUMA_ADMIN_PASSWORD` | dev, prod | secret | `homelab/KUMA_ADMIN_PASSWORD/<env>` | set 2026-10-20 | login `admin` of the Uptime Kuma add-on; `utils/kuma-sync.py` sets it up on a fresh Kuma |
| `KUMA_PUSH_SECRET` | dev, prod | secret | `homelab/KUMA_PUSH_SECRET/<env>` | set 2026-10-20 | seed of the Kuma push tokens (backup freshness); the NAS gets it from the deploy |
| `SMTP_USERNAME` | prod | secret | `homelab/SMTP_USERNAME/prod` | set 2026-10-21 | Proton address `homelab-prod@dkhomelabserver.xyz` (owner); sender of Kuma, Diun, Beszel mail |
| `SMTP_PASSWORD` | prod | secret | `homelab/SMTP_PASSWORD/prod` | set 2026-10-21 | Proton SMTP token of `SMTP_USERNAME` (owner) |
| `CLOUDFLARE_API_TOKEN` | prod | secret | `homelab/CLOUDFLARE_API_TOKEN/prod` | planned | Zone.DNS edit on `dkhomelabserver.xyz` only; Caddy wildcard certificate (owner); without it prod keeps proxy and auth off |
| `OPNSENSE_BACKUP_SSH_PRIV` | prod | secret | `homelab/OPNSENSE_BACKUP_SSH_PRIV/prod` | set 2026-10-22 | NAS key for `config.xml`, forced command on the router. GitHub env prod and Bitwarden both have it. |
| `OPNSENSE_ADMIN_SSH_PRIV` | prod | secret | `homelab/OPNSENSE_ADMIN_SSH_PRIV/prod` | cache 2026-10-22 | `~/.ssh/daveadmin`, router root shell. Bitwarden via the cache queue. Not a GitHub secret. |
| `PVE_ROOT_SSH_PRIV` | prod | secret | `homelab/PVE_ROOT_SSH_PRIV/prod` | cache 2026-10-22 | `~/.ssh/homelab_prod_pve_ed25519`, root on the prod Proxmox host. Bitwarden via the cache queue. Not a GitHub secret. |
| `NIC_MAIL_SSH_PRIV` | prod | secret | `homelab/NIC_MAIL_SSH_PRIV/prod` | cache 2026-10-22 | `/root/.ssh/homelab-nic-mail` on Proxmox. Forced command mails NIC growth. Bitwarden via the cache queue. Not a GitHub secret. |
| `PORTAINER_ADMIN_PASSWORD` | dev | secret | `homelab/PORTAINER_ADMIN_PASSWORD/dev` | set | generated 2026-09-10 |
| `PGADMIN_PASSWORD` | dev | secret | `homelab/PGADMIN_PASSWORD/dev` | set | generated 2026-09-10 |
| `HOMARR_ADMIN_PASSWORD` | dev | secret | `homelab/HOMARR_ADMIN_PASSWORD/dev` | set | generated 2026-09-10; rotated same day |
| `AUTHELIA_ADMIN_PASSWORD` | dev | secret | `homelab/AUTHELIA_ADMIN_PASSWORD/dev` | set | generated 2026-09-10 |
| `LINKWARDEN_ADMIN_PASSWORD` | dev | secret | `homelab/LINKWARDEN_ADMIN_PASSWORD/dev` | set | generated 2026-09-10 |
| `IMMICH_ADMIN_PASSWORD` | dev | secret | `homelab/IMMICH_ADMIN_PASSWORD/dev` | set | generated 2026-09-10 |
| `JELLYFIN_ADMIN_PASSWORD` | dev | secret | `homelab/JELLYFIN_ADMIN_PASSWORD/dev` | set | generated 2026-09-10 |
| `NAVIDROME_ADMIN_PASSWORD` | dev | secret | `homelab/NAVIDROME_ADMIN_PASSWORD/dev` | set | generated 2026-09-10 |
| `SYNCTHING_ADMIN_PASSWORD` | dev | secret | `homelab/SYNCTHING_ADMIN_PASSWORD/dev` | set | generated 2026-09-10 |
| `BESZEL_ADMIN_PASSWORD` | dev | secret | `homelab/BESZEL_ADMIN_PASSWORD/dev` | set | generated 2026-09-10 |
| `HOMARR_SECRET_KEY` | dev | secret | `homelab/HOMARR_SECRET_KEY/dev` | set | generated 2026-09-10 |
| `LINKWARDEN_SECRET` | dev | secret | `homelab/LINKWARDEN_SECRET/dev` | set | generated 2026-09-10 |
| `AUTHELIA_JWT_SECRET` | dev | secret | `homelab/AUTHELIA_JWT_SECRET/dev` | set | generated 2026-09-10 |
| `AUTHELIA_SESSION_SECRET` | dev | secret | `homelab/AUTHELIA_SESSION_SECRET/dev` | set | generated 2026-09-10 |
| `AUTHELIA_STORAGE_KEY` | dev | secret | `homelab/AUTHELIA_STORAGE_KEY/dev` | set | generated 2026-09-10 |
| `GROCERY_DB_PASSWORD` | dev | secret | `homelab/GROCERY_DB_PASSWORD/dev` | set | F4/F7 |
| `GROCERY_SECRET_KEY` | dev | secret | `homelab/GROCERY_SECRET_KEY/dev` | set | generated 2026-10-21; EasyToDo v2 data encryption key (hex64), keep stable |
| `GROCERY_ADMIN_PASSWORD` | dev | secret | `homelab/GROCERY_ADMIN_PASSWORD/dev` | set | generated 2026-10-21; EasyToDo v2 admin (`inject: bootstrap`, `portainer.sh`) |
| `GROCERY_PROTON_SMTP_TOKEN` | dev | secret | `homelab/GROCERY_PROTON_SMTP_TOKEN/dev` | set 2026-10-21 | Proton SMTP token of todo-grocery@dkhomelabserver.xyz; optional |
| `IMMICH_DB_PASSWORD` | dev | secret | `homelab/IMMICH_DB_PASSWORD/dev` | set | F4/F7 |
| `SAMBA_ADMIN_PASSWORD` | dev | secret | `homelab/SAMBA_ADMIN_PASSWORD/dev` | set 2026-10-19 | Samba login `admin` (`inject: ansible`, `deploy-storage.yml`); also in `~/.homelab-secrets/dev/`; Bitwarden copy by the operator |
| `PORTAINER_ADMIN_PASSWORD` | prod | secret | `homelab/PORTAINER_ADMIN_PASSWORD/prod` | set | generated 2026-09-11 |
| `PGADMIN_PASSWORD` | prod | secret | `homelab/PGADMIN_PASSWORD/prod` | set | generated 2026-09-11 |
| `HOMARR_ADMIN_PASSWORD` | prod | secret | `homelab/HOMARR_ADMIN_PASSWORD/prod` | set | generated 2026-09-11 |
| `AUTHELIA_ADMIN_PASSWORD` | prod | secret | `homelab/AUTHELIA_ADMIN_PASSWORD/prod` | set | generated 2026-09-11 |
| `LINKWARDEN_ADMIN_PASSWORD` | prod | secret | `homelab/LINKWARDEN_ADMIN_PASSWORD/prod` | set | generated 2026-09-11 |
| `IMMICH_ADMIN_PASSWORD` | prod | secret | `homelab/IMMICH_ADMIN_PASSWORD/prod` | set | generated 2026-09-11 |
| `JELLYFIN_ADMIN_PASSWORD` | prod | secret | `homelab/JELLYFIN_ADMIN_PASSWORD/prod` | set | generated 2026-09-11 |
| `NAVIDROME_ADMIN_PASSWORD` | prod | secret | `homelab/NAVIDROME_ADMIN_PASSWORD/prod` | set | generated 2026-09-11 |
| `SYNCTHING_ADMIN_PASSWORD` | prod | secret | `homelab/SYNCTHING_ADMIN_PASSWORD/prod` | set | generated 2026-09-11 |
| `BESZEL_ADMIN_PASSWORD` | prod | secret | `homelab/BESZEL_ADMIN_PASSWORD/prod` | set | generated 2026-09-11 |
| `IMMICH_DB_PASSWORD` | prod | secret | `homelab/IMMICH_DB_PASSWORD/prod` | set | generated 2026-09-11 |
| `GROCERY_DB_PASSWORD` | prod | secret | `homelab/GROCERY_DB_PASSWORD/prod` | set | generated 2026-09-11 |
| `GROCERY_SECRET_KEY` | prod | secret | `homelab/GROCERY_SECRET_KEY/prod` | set | generated 2026-10-21; EasyToDo v2 data encryption key (hex64), keep stable |
| `GROCERY_ADMIN_PASSWORD` | prod | secret | `homelab/GROCERY_ADMIN_PASSWORD/prod` | set | generated 2026-10-21; EasyToDo v2 admin (`inject: bootstrap`, `portainer.sh`) |
| `GROCERY_PROTON_SMTP_TOKEN` | prod | secret | `homelab/GROCERY_PROTON_SMTP_TOKEN/prod` | set 2026-10-21 | Proton SMTP token of todo-grocery@dkhomelabserver.xyz; optional |
| `HOMARR_SECRET_KEY` | prod | secret | `homelab/HOMARR_SECRET_KEY/prod` | set | generated 2026-09-11 |
| `LINKWARDEN_SECRET` | prod | secret | `homelab/LINKWARDEN_SECRET/prod` | set | generated 2026-09-11 |
| `AUTHELIA_JWT_SECRET` | prod | secret | `homelab/AUTHELIA_JWT_SECRET/prod` | set | generated 2026-09-11 |
| `AUTHELIA_SESSION_SECRET` | prod | secret | `homelab/AUTHELIA_SESSION_SECRET/prod` | set | generated 2026-09-11 |
| `AUTHELIA_STORAGE_KEY` | prod | secret | `homelab/AUTHELIA_STORAGE_KEY/prod` | set | generated 2026-09-11 |
| `SAMBA_ADMIN_PASSWORD` | prod | secret | `homelab/SAMBA_ADMIN_PASSWORD/prod` | set 2026-10-19 | Samba login `admin` (`inject: ansible`, `deploy-storage.yml`); also in `~/.homelab-secrets/prod/`; Bitwarden copy by the operator |

---

## GitHub Environments — variables

| Name | GH env | Type | Bitwarden | Status | Notes |
|------|--------|------|-----------|--------|-------|
| `PROXMOX_API_URL` | dev | variable | — | set | placeholder URL — F3 |
| `PROXMOX_API_URL` | prod | variable | — | set | placeholder URL — F3 |
| `PROXMOX_API_URL` | prod-plan | variable | — | set | copy of prod |
| `PROXMOX_API_TOKEN_ID` | dev | variable | — | set | F1 |
| `PROXMOX_API_TOKEN_ID` | prod | variable | — | set | F1 |
| `PROXMOX_API_TOKEN_ID` | prod-plan | variable | — | set | `homelab-prod@pam!plan` |
| `PROXMOX_SSH_USERNAME` | dev | variable | — | set | F1 |
| `PROXMOX_SSH_USERNAME` | prod | variable | — | set | F1 |
| `PROXMOX_SSH_USERNAME` | prod-plan | variable | — | set | copy of prod; no `PROXMOX_SSH_PASSWORD` here, the workflow passes a dummy |
| `UBUNTU_DOCKER_SSH_PUB` | dev | variable | — | set | F1 |
| `UBUNTU_DOCKER_SSH_PUB` | prod | variable | — | set 2026-10-19 | `~/.ssh/homelab_prod_ed25519.pub` |
| `UBUNTU_DOCKER_SSH_PUB` | prod-plan | variable | — | set | copy of prod |

---

## Terraform Cloud (org `dkhomelabserver`, workspace `homelab`)

| Name (TFC Variable Set) | Sensitive | Source | Status | Notes |
|-------------------------|-----------|--------|--------|-------|
| `TF_VAR_proxmox_api_url` | no | GH variable prod | planned | F3 |
| `TF_VAR_proxmox_api_token_id` | no | GH variable prod | planned | F3 |
| `TF_VAR_proxmox_api_token_secret` | yes | GH secret prod | planned | F3 |
| `TF_VAR_proxmox_ssh_username` | no | GH variable prod | planned | F3 |
| `TF_VAR_proxmox_ssh_password` | yes | GH secret prod | planned | F3 |

**F1:** workspace execution mode **Local** ✅ 2026-06-29 (before prod apply from self-hosted runner).

---

## Outside GitHub (do not commit)

| Item | Location | Notes |
|------|----------|-------|
| OPNsense API / config | router | backup config.xml — F2/F5 |
| WireGuard keys | OPNsense | already on router |
| `~/.terraform.d/credentials.tfrc.json` | laptop | token copy in Bitwarden |
| `~/.config/rclone/rclone.conf` | NAS / prod runner | F5; description in Bitwarden |

---

## Legacy — do not restore

Removed in A0 (2026-06-11): `BW_ACCESS_TOKEN`, `BW_CLIENTID`, `BW_CLIENTSECRET` (repo), legacy `PROXMOX_*`, `POSTGRES_*`, `UBUNTU_*`, `SSL_*` in env dev/prod.

---

*Last updated: 2026-09-11 — vault holds the cache sync plus `POSTGRES_PASSWORD` / F1 (operator confirmed). Staging `~/homelab-bitwarden-*.txt` shredded. `RCLONE_CONFIG` is in GH prod + cache.*
