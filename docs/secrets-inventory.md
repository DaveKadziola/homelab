# Secrets inventory — homelab v2

> **Status:** name template (F0-10) — **no values**.  
> **Procedure:** generate locally → Bitwarden `homelab/<NAME>/<env>` → `gh secret set` / `gh variable set`.  
> **Related:** [manual-setup.md](manual-setup.md) (F0/F1), greenfield v2 plan.

**Rule:** GitHub Secrets are **write-only** — after `gh secret set` you cannot read values back from GH. A copy in Bitwarden is mandatory.

Helper scripts:

| Script | Purpose |
|--------|---------|
| `utils/export-secrets-for-bitwarden.sh` | Export to `.txt` for Bitwarden (`--regenerate` for new GH-only secrets) |
| `utils/bootstrap-f1-secrets.sh` | Push secrets/variables to GitHub (values not printed) |


## Legend

| Column | Meaning |
|--------|---------|
| **GH env** | `dev` \| `prod` \| `repo` \| — (not in GH) |
| **Type** | `secret` \| `variable` |
| **Status** | `planned` \| `set` \| `N/A` |
| **Bitwarden** | path in Password Manager |

---

## GitHub Environments — secrets

| Name | GH env | Type | Bitwarden | Status | Notes |
|------|--------|------|-----------|--------|-------|
| `POSTGRES_PASSWORD` | dev | secret | `homelab/POSTGRES_PASSWORD/dev` | set | F1 2026-06-29 |
| `POSTGRES_PASSWORD` | prod | secret | `homelab/POSTGRES_PASSWORD/prod` | set | F1 2026-06-29 |
| `PROXMOX_API_TOKEN_SECRET` | dev | secret | `homelab/PROXMOX_API_TOKEN_SECRET/dev` | set | placeholder — update at F3 |
| `PROXMOX_API_TOKEN_SECRET` | prod | secret | `homelab/PROXMOX_API_TOKEN_SECRET/prod` | set | placeholder — update at F3 |
| `PROXMOX_SSH_PASSWORD` | dev | secret | `homelab/PROXMOX_SSH_PASSWORD/dev` | set | placeholder |
| `PROXMOX_SSH_PASSWORD` | prod | secret | `homelab/PROXMOX_SSH_PASSWORD/prod` | set | placeholder |
| `UBUNTU_DOCKER_PASSWORD` | dev | secret | `homelab/UBUNTU_DOCKER_PASSWORD/dev` | set | F1 |
| `UBUNTU_DOCKER_PASSWORD` | prod | secret | `homelab/UBUNTU_DOCKER_PASSWORD/prod` | set | F1 |
| `UBUNTU_DOCKER_SSH_PRIV` | dev | secret | `homelab/UBUNTU_DOCKER_SSH_PRIV/dev` | set | `~/.ssh/homelab_dev_ed25519` |
| `UBUNTU_DOCKER_SSH_PRIV` | prod | secret | `homelab/UBUNTU_DOCKER_SSH_PRIV/prod` | set | placeholder — replace at F3 |
| `TF_API_TOKEN` | prod | secret | `homelab/TF_API_TOKEN/prod` | set | F1 |
| `SSL_CERT` | prod | secret | `homelab/SSL_CERT/prod` | planned | optional; legacy backup |
| `SSL_CHAIN` | prod | secret | `homelab/SSL_CHAIN/prod` | planned | optional |
| `SSL_PKEY` | prod | secret | `homelab/SSL_PKEY/prod` | planned | optional |
| `RCLONE_CONFIG` | prod | secret | `homelab/RCLONE_CONFIG/prod` | planned | F5; base64 `rclone.conf` — job SKIPs until set |
| `HA_TOKEN` | prod | secret | `homelab/HA_TOKEN/prod` | planned | F5 HA Supervisor pull; T620 not flashed from this repo |
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
| `IMMICH_DB_PASSWORD` | dev | secret | `homelab/IMMICH_DB_PASSWORD/dev` | set | F4/F7 |

---

## GitHub Environments — variables

| Name | GH env | Type | Bitwarden | Status | Notes |
|------|--------|------|-----------|--------|-------|
| `PROXMOX_API_URL` | dev | variable | — | set | placeholder URL — F3 |
| `PROXMOX_API_URL` | prod | variable | — | set | placeholder URL — F3 |
| `PROXMOX_API_TOKEN_ID` | dev | variable | — | set | F1 |
| `PROXMOX_API_TOKEN_ID` | prod | variable | — | set | F1 |
| `PROXMOX_SSH_USERNAME` | dev | variable | — | set | F1 |
| `PROXMOX_SSH_USERNAME` | prod | variable | — | set | F1 |
| `UBUNTU_DOCKER_SSH_PUB` | dev | variable | — | set | F1 |
| `UBUNTU_DOCKER_SSH_PUB` | prod | variable | — | set | placeholder — F3 |

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

*Last updated: F9 2026-09-10 — F7 app secrets are in GH env `dev`. Copy the laptop cache into Bitwarden; GH cannot read them back.*
