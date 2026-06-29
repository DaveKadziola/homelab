# Inwentarz sekretów — homelab v2

> **Status:** szablon nazw (F0-10) — **bez wartości**.  
> **Procedura:** generuj lokalnie → Bitwarden `homelab/<NAZWA>/<env>` → `gh secret set` / `gh variable set`.  
> **Powiązane:** [manual-setup.md](manual-setup.md) (F0/F1), plan greenfield v2.

**Zasada:** GitHub Secrets są **write-only** — po `gh secret set` wartości nie odczytasz z GH. Kopia w Bitwarden jest obowiązkowa.

## Legenda

| Kolumna | Znaczenie |
|---------|-----------|
| **GH env** | `dev` \| `prod` \| `repo` \| — (nie w GH) |
| **Typ** | `secret` \| `variable` |
| **Status** | `planned` \| `set` \| `N/A` |
| **Bitwarden** | ścieżka w Password Manager |

---

## GitHub Environments — secrets

| Nazwa | GH env | Typ | Bitwarden | Status | Uwagi |
|-------|--------|-----|-----------|--------|-------|
| `POSTGRES_PASSWORD` | dev | secret | `homelab/POSTGRES_PASSWORD/dev` | planned | F1 |
| `POSTGRES_PASSWORD` | prod | secret | `homelab/POSTGRES_PASSWORD/prod` | planned | F1 |
| `PROXMOX_API_TOKEN_SECRET` | dev | secret | `homelab/PROXMOX_API_TOKEN_SECRET/dev` | planned | F1 |
| `PROXMOX_API_TOKEN_SECRET` | prod | secret | `homelab/PROXMOX_API_TOKEN_SECRET/prod` | planned | F1 |
| `PROXMOX_SSH_PASSWORD` | dev | secret | `homelab/PROXMOX_SSH_PASSWORD/dev` | planned | F1 |
| `PROXMOX_SSH_PASSWORD` | prod | secret | `homelab/PROXMOX_SSH_PASSWORD/prod` | planned | F1 |
| `UBUNTU_DOCKER_PASSWORD` | dev | secret | `homelab/UBUNTU_DOCKER_PASSWORD/dev` | planned | F1 |
| `UBUNTU_DOCKER_PASSWORD` | prod | secret | `homelab/UBUNTU_DOCKER_PASSWORD/prod` | planned | F1 |
| `UBUNTU_DOCKER_SSH_PRIV` | dev | secret | `homelab/UBUNTU_DOCKER_SSH_PRIV/dev` | planned | F1; lub tylko lokalnie `~/.ssh/` |
| `UBUNTU_DOCKER_SSH_PRIV` | prod | secret | `homelab/UBUNTU_DOCKER_SSH_PRIV/prod` | planned | F1 |
| `TF_API_TOKEN` | prod | secret | `homelab/TF_API_TOKEN/prod` | planned | wartość w Bitwarden ✅; `gh secret set` w F1 |
| `SSL_CERT` | prod | secret | `homelab/SSL_CERT/prod` | planned | opcjonalnie; legacy backup |
| `SSL_CHAIN` | prod | secret | `homelab/SSL_CHAIN/prod` | planned | opcjonalnie |
| `SSL_PKEY` | prod | secret | `homelab/SSL_PKEY/prod` | planned | opcjonalnie |
| `RCLONE_CONFIG` | prod | secret | `homelab/RCLONE_CONFIG/prod` | planned | F5; base64 `rclone.conf` |

---

## GitHub Environments — variables

| Nazwa | GH env | Typ | Bitwarden | Status | Uwagi |
|-------|--------|-----|-----------|--------|-------|
| `PROXMOX_API_URL` | dev | variable | — | planned | F1 |
| `PROXMOX_API_URL` | prod | variable | — | planned | F1 |
| `PROXMOX_API_TOKEN_ID` | dev | variable | — | planned | F1 |
| `PROXMOX_API_TOKEN_ID` | prod | variable | — | planned | F1 |
| `PROXMOX_SSH_USERNAME` | dev | variable | — | planned | F1 |
| `PROXMOX_SSH_USERNAME` | prod | variable | — | planned | F1 |
| `UBUNTU_DOCKER_SSH_PUB` | dev | variable | — | planned | F1 |
| `UBUNTU_DOCKER_SSH_PUB` | prod | variable | — | planned | F1 |

---

## Terraform Cloud (org `dkhomelabserver`, workspace `homelab`)

| Nazwa (TFC Variable Set) | Sensitive | Źródło | Status | Uwagi |
|--------------------------|-----------|--------|--------|-------|
| `TF_VAR_proxmox_api_url` | nie | GH variable prod | planned | F3 |
| `TF_VAR_proxmox_api_token_id` | nie | GH variable prod | planned | F3 |
| `TF_VAR_proxmox_api_token_secret` | tak | GH secret prod | planned | F3 |
| `TF_VAR_proxmox_ssh_username` | nie | GH variable prod | planned | F3 |
| `TF_VAR_proxmox_ssh_password` | tak | GH secret prod | planned | F3 |

**F1:** workspace execution mode **remote → Local** przed prod apply z self-hosted runnera.

---

## Poza GitHub (nie commitować)

| Element | Gdzie | Uwagi |
|---------|-------|-------|
| OPNsense API / config | router | backup config.xml — F2/F5 |
| WireGuard keys | OPNsense | już na routerze |
| `~/.terraform.d/credentials.tfrc.json` | laptop | kopia tokenu w Bitwarden |
| `~/.config/rclone/rclone.conf` | NAS / runner prod | F5; opis w Bitwarden |

---

## Legacy — nie przywracać

Usunięte w A0 (2026-06-11): `BW_ACCESS_TOKEN`, `BW_CLIENTID`, `BW_CLIENTSECRET` (repo), legacy `PROXMOX_*`, `POSTGRES_*`, `UBUNTU_*`, `SSL_*` w env dev/prod.

---

*Ostatnia aktualizacja: F0-10 — szablon nazw. Aktualizuj **Status** i datę rotacji po każdym `gh secret set`.*
