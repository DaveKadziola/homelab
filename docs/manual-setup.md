# Manual laptop setup — F0 sprint

> **Status:** reference document for **F0 planning and sprint**.  
> **Work through during F0 sprint** — check off steps during the F0 sprint, before starting F1.  
> **Related:** greenfield v2 plan, F0→F1 gate, [`README.md`](../README.md) (links here in the "Prerequisites" section).

**Repo:** [DaveKadziola/homelab](https://github.com/DaveKadziola/homelab)  
**Target working branch:** `homelab-v2` (from `main`)

---

## F0 sprint — task overview

| ID | Task | Sprint | Blocks F1? | Status |
|----|------|--------|------------|--------|
| [F0-01](#f0-01--laptop-tool-audit) | Laptop tool audit | F0 | yes | [x] |
| [F0-02](#f0-02--install-missing-packages) | Install missing packages | F0 | yes | [x] |
| [F0-03](#f0-03--user-groups-and-libvirt) | User groups + libvirt | F0 | yes | [x] |
| [F0-04](#f0-04--github-cli-and-repo-access) | GitHub CLI and repo access | F0 | yes | [x] |
| [F0-04b](#f0-04b--github-environments-devprod-a7) | GitHub Environments dev/prod (A7) | F0 | yes | [x] |
| [F0-04c](#f0-04c--terraform-cloud-workspace-a8) | Terraform Cloud workspace (A8) | F0 | yes | [x] |
| [F0-04d](#f0-04d--pcloud--rclone-auth-a9) | pCloud + rclone auth (A9) | F0 | no* | [~] |
| [F0-04e](#f0-04e--bitwarden-vault--2fa-a10) | Bitwarden vault + 2FA (A10) | F0 | yes | [x] |
| [F0-05](#f0-05--legacy-secretsvariables-audit) | Legacy secrets/variables audit | F0 | yes | [x] |
| [F0-06](#f0-06--bitwarden-backup-before-deletion) | Bitwarden backup before deletion | F0 | yes | [x] |
| [F0-07](#f0-07--remove-legacy-secretsvariables) | Remove legacy secrets/variables | F0 | yes | [x] |
| [F0-08](#f0-08--self-hosted-runner-legacy) | Self-hosted runner (legacy) | F0 | no* | [x] N/A |
| [F0-09](#f0-09--create-homelab-v2-branch) | Create `homelab-v2` branch | F0 | yes | [x] |
| [F0-10](#f0-10--commit-docs-on-homelab-v2) | Commit `docs/` on `homelab-v2` | F0 | recommended | [x] |
| [F0-11](#f0-11--bitwarden-preparation) | Bitwarden preparation | F0 | yes | [x] |
| [F0-12](#f0-12--f0-gate--final-verification) | F0 gate — final verification | F0 | yes | [x] |

\* F0-08 only if a runner exists in the repo.  
\* F0-04d blocks **F5** (backup jobs), not the F0→F1 gate — can be deferred to the F5 sprint, but a pCloud account is worth setting up early.

**Outside F0 (F1):** create dev VM, new `gh secret set`, GitHub Actions pipeline — see plan, F1 phase.

---

## F0-01 — Laptop tool audit

**Goal:** know what is already installed before installing anything else.

**Commands:**

```bash
for cmd in git gh terraform ansible ansible-playbook ansible-lint docker virsh virt-install openssl ssh-keygen; do
  printf '%-20s' "$cmd:"; command -v "$cmd" || echo "MISSING"
done
docker compose version 2>/dev/null || echo "docker compose: MISSING"
groups
```

**Definition of done:**

- [x] OK / MISSING tool list recorded (2026-06-11 — below)
- [x] Known which F0-02 steps are needed → **ansible-lint**, **libvirtd**, `default` network

**Audit result (2026-06-11):**

| Tool | Status | Version / notes |
|------|--------|-----------------|
| `git` | OK | 2.47.3 |
| `gh` | OK | 2.46.0 |
| `terraform` | OK | 1.15.6 |
| `ansible` | OK | core 2.19.4 |
| `ansible-playbook` | OK | `/usr/bin/ansible-playbook` |
| `ansible-lint` | **MISSING** | → F0-02 (`pipx install ansible-lint`) |
| `docker` | OK | |
| `docker compose` | OK | v5.1.4 |
| `virsh` | OK | 11.3.0 |
| `virt-install` | OK | |
| `openssl` | OK | |
| `ssh-keygen` | OK | |
| `rclone` | OK | 1.60.1-DEV |
| `bw` | MISSING | optional (A10 gate closed without CLI) |

**Groups:** `kvm`, `libvirt`, `docker` — OK

**Libvirt:** `libvirtd` = **active** ✅; `default` network = **active** + autostart ✅ (2026-06-11, `qemu:///system`)

**Note:** use `virsh -c qemu:///system` if plain `virsh net-list` returns an empty list (session vs system connection).

**Target state (F1):** all items from the [tools table](#reference--required-tools) present.

---

## F0-02 — Install missing packages

**Goal:** fill gaps from F0-01.

**Dependencies:** F0-01

**Debian 13 — example:**

```bash
sudo apt update
sudo apt install -y git gh ansible openssl openssh-client \
  libvirt-clients virtinst qemu-kvm libvirt-daemon-system

# ansible-lint — if not in apt:
sudo apt install -y pipx
pipx ensurepath
pipx install ansible-lint
```

**Verification:**

```bash
git --version && gh --version && terraform version && ansible --version
ansible-lint --version && docker compose version && virsh --version
```

**Definition of done:**

- [x] All required tools return a version (2026-06-11)
- [x] `ansible-lint` — installed via `pipx` (26.4.0); ensure `~/.local/bin` is in `PATH`

---

## F0-03 — User groups and libvirt

**Goal:** libvirt and Docker work without unnecessary sudo; `default` network ready for dev VM (the VM itself is created in **F1**).

**Dependencies:** F0-02

**Steps:**

```bash
# 1. Groups (if missing from groups)
sudo usermod -aG libvirt,kvm,docker "$USER"
# → log out / log in or: newgrp libvirt

# 2. libvirt daemon
sudo systemctl enable --now libvirtd
systemctl is-active libvirtd   # expected: active

# 3. default network
virsh net-list --all
sudo virsh net-start default
sudo virsh net-autostart default
# alternative: ./utils/start_qemu_default_net
```

**Definition of done:**

- [x] User in `libvirt`, `kvm`, `docker` groups (F0-01)
- [x] `libvirtd` = **active** (2026-06-11)
- [x] `default` network = **active** + **autostart** (`virsh -c qemu:///system net-list --all`)
- [x] `virsh -c qemu:///system list --all` works without error

---

## F0-04 — GitHub CLI and repo access

**Goal:** `gh` logged in with permissions for secrets and workflows.

**Dependencies:** F0-02

**Steps:**

```bash
gh auth login
gh auth status
# required scope: repo, workflow

cd /path/to/homelab
git fetch origin
git checkout main
git pull
```

**Definition of done:**

- [x] `gh auth status` — **DaveKadziola**, scope `repo` + `workflow` (2026-06-11)
- [x] `git fetch origin` OK
- [x] Local branch: **`homelab-v2`** (tracking `origin/homelab-v2`, `15102bd`); `docs/` **untracked** → F0-10

**Verification (2026-06-11):**

| Item | Status |
|------|--------|
| `gh auth` | OK — `repo`, `workflow` |
| `origin/main` | accessible (`15102bd`) |
| `origin/homelab-v2` | **OK** ✅ F0-09 |
| Local branch | `homelab-v2`; `?? docs/` |

---

## F0-04b — GitHub Environments dev/prod (A7)

**Goal:** `dev` and `prod` environments ready for v2 CI — approval on prod, prod deploy branch = `main`.

**Dependencies:** F0-04, F0-07 (recommended: empty env before first v2 secret)

**Verification (2026-06-11):**

| Item | Status |
|------|--------|
| Repo | `DaveKadziola/homelab`, **public**, default branch **`main`** |
| `gh auth` | OK — scope `repo`, `workflow` |
| Environment `dev` | exists, secrets empty |
| Environment `prod` | exists, secrets empty |
| Prod — required reviewer | `DaveKadziola` |
| Prod — deployment branches | **`main`** only (plan says `master` — repo uses `main`) |
| Actions | enabled, `allowed_actions: all` |
| `gh secret set --env dev` | OK (test removed) |

**Prod — approval + branch policy (one-time, via API):**

```bash
# Reviewer ID: gh api user --jq .id
gh api -X PUT repos/DaveKadziola/homelab/environments/prod \
  --input - <<'EOF'
{
  "prevent_self_review": false,
  "reviewers": [{"type": "User", "id": 194847688}],
  "deployment_branch_policy": {
    "protected_branches": false,
    "custom_branch_policies": true
  }
}
EOF

gh api -X POST repos/DaveKadziola/homelab/environments/prod/deployment-branch-policies \
  --input - <<'EOF'
{"name": "main"}
EOF
```

**After F0-09** (`homelab-v2` branch): optionally restrict **dev** deploy to branch `homelab-v2` — same `deployment-branch-policies` on env `dev`.

**Definition of done:**

- [x] Environments `dev` + `prod` exist
- [x] Prod requires approval before deploy
- [x] Prod accepts deploy only from branch `main`
- [x] `gh secret set --env dev` works (v2 secrets in F1)

---

## F0-04c — Terraform Cloud workspace (A8)

**Goal:** HCP Terraform (Terraform Cloud) account + **prod** workspace on empty v2 state — **no** legacy tfstate import.

**Dependencies:** F0-04 (GitHub account OK); F0-07 recommended (no secret collisions in GH)

**Architecture (v2 plan):**

| Item | Target value |
|------|--------------|
| **TFC org** | **`dkhomelabserver`** (decision 2026-06-11) |
| **Prod workspace** | **`homelab`** (org `dkhomelabserver`) |
| **Dev workspace** | **none** — dev TF on laptop (libvirt), local state; TFC **prod only** |
| **Repo backend** | `cloud { ... }` in `terraform/versions.tf` — in **F1**, not now |
| **GH secret** | `TF_API_TOKEN` → env **prod** (F1); **not** in repo |

**Verification (2026-06-11 — without user tokens):**

| Item | Status |
|------|--------|
| `terraform` CLI | v1.14.6 (`/usr/bin/terraform`) |
| `~/.terraform.d/credentials.tfrc.json` | **OK** (2026-06-11) |
| Workspace **`homelab`** | org `dkhomelabserver`, `resource-count: 0`, auto-apply OFF, execution **remote** (→ Local in F1) |

**Manual steps (one-time):**

1. **Account:** [app.terraform.io/signup](https://app.terraform.io/signup) — **Free** plan sufficient (1 org, multiple workspaces within free limit).
2. **Organization:** org **`dkhomelabserver`** — already created ✅
3. **Prod workspace:**
   - Name: **`homelab`** — created ✅
   - **Execution mode:** currently **remote** → set **Local** in **F1** (apply from self-hosted runner in LAN)
   - **Terraform version:** ≥ 1.8.0 (repo: `required_version = ">= 1.8.0"`).
   - **Auto apply:** **OFF** (apply only via `infra-apply-prod.yml` + GH env prod approval).
   - **State:** empty — **do not** import old `terraform.tfstate` from legacy CI.
4. **API token (User settings → Tokens):**
   ```bash
   terraform login
   # alternative: paste token manually into ~/.terraform.d/credentials.tfrc.json
   ```
   Copy token to Bitwarden (`homelab/TF_API_TOKEN/prod`), then in **F1**:
   ```bash
   gh secret set TF_API_TOKEN --env prod --body "$TOKEN"
   unset TOKEN
   ```
5. **Verification after login:**
   ```bash
   # org: dkhomelabserver
   curl -s \
     --header "Authorization: Bearer $(python3 -c "import json;print(json.load(open('$HOME/.terraform.d/credentials.tfrc.json'))['credentials']['app.terraform.io']['token'])")" \
     "https://app.terraform.io/api/v2/organizations/dkhomelabserver/workspaces/homelab" \
     | python3 -m json.tool | head -20
   ```
   Expected: JSON with `"name": "homelab"`, no `"errors"`.

**Variable Set (optional now, required before first prod apply in F3):**

In TFC create a Variable Set attached to **`homelab`** — values **later** from Bitwarden / `gh secret set` (F1), not in repo:

| TFC variable | Sensitive | Source (F1+) |
|--------------|-----------|--------------|
| `TF_VAR_proxmox_api_url` | no | GH variable prod |
| `TF_VAR_proxmox_api_token_id` | no | GH variable prod |
| `TF_VAR_proxmox_api_token_secret` | yes | GH secret prod |
| `TF_VAR_proxmox_ssh_username` | no | GH variable prod |
| `TF_VAR_proxmox_ssh_password` | yes | GH secret prod |
| `TF_VAR_ubuntu_docker_password` | yes | GH secret prod |
| `TF_VAR_ubuntu_docker_ssh_pub` | no | GH variable prod |
| `TF_VAR_ssl_*` | yes | GH secret prod (if cert setup in TF) |

**Definition of done:**

- [x] HCP Terraform account + org **`dkhomelabserver`**
- [x] Workspace **`homelab`** exists, empty state (2026-06-11)
- [x] `terraform login` OK
- [x] Token in Bitwarden (`homelab/TF_API_TOKEN/prod`)
- [x] API returns workspace — verified 2026-06-11
- [ ] `TF_API_TOKEN` in GH env prod — **F1** (does not block closing A8 account/workspace)

---

## F0-04d — pCloud + rclone auth (A9)

**Goal:** pCloud account + configured **rclone** remote for offsite backups (decision **B16**: rclone → pCloud, not ZeroByte).

**Dependencies:** F0-04 (optionally F0-11 Bitwarden — OAuth token copy); **does not** block F0→F1 gate, blocks **F5** (NAS backup jobs + offsite sync).

**Architecture (v2 plan):**

| Item | Target value |
|------|--------------|
| **Tool** | **rclone** (one-way copy/sync to cloud) |
| **Backend** | pCloud (`type = pcloud`) |
| **Remote name** | **`pcloud`** — use consistently in F5 scripts and crons |
| **Offsite path** | **`homelab-backups/`** on pCloud (account root or subfolder) |
| **Subfolders (F5)** | `vzdump/`, `postgres/`, `homeassistant/`, `opnsense/`, `repo-zip/` — **DR only** (no full media libraries; media already on pCloud separately) |
| **Local (Purple 4 TB)** | Retention **2 newest** backups (A15); offsite schedule — *TBD* in F5 |
| **GH secret** | **`RCLONE_CONFIG`** → env **prod** (F5) — base64 of entire `rclone.conf` **or** `[pcloud]` section only; **not** in repo |
| **GH env dev** | **none** — dev does not send offsite backups |

**Verification (2026-06-11 — without user credentials):**

| Item | Status |
|------|--------|
| `rclone` CLI | v1.60.1-DEV (`/usr/bin/rclone`, Debian package) |
| `~/.config/rclone/rclone.conf` | file exists, **empty** (0 B) — no `[pcloud]` section |
| Remote `pcloud` | **no** — `rclone listremotes` empty |
| pCloud account | ✅ active — **500 GB free** (user 2026-06-11) |
| `gh secret list` (repo + dev + prod) | empty — no `RCLONE_*` (A0 ✅) |
| `.github/workflows/force-proxmox-resource-backup.yml` | legacy placeholder (no rclone) |

**Manual steps (one-time):**

1. **pCloud account:** ✅ account active — **500 GB free** (2026-06-11); homelab DR backup-only **~160 GB** (2× retention, no media) fits with large margin — see [A15 Storage sizing](#reference--a15-storage-sizing-f3f5). **Media (Immich/music/video) already backed up to pCloud separately** — homelab rclone does not duplicate them.
2. **Install rclone** (if missing after F0-01):
   ```bash
   sudo apt update && sudo apt install -y rclone
   rclone version
   ```
3. **Configure remote (interactive — requires pCloud login):**
   ```bash
   rclone config
   # n) New remote
   # name: pcloud
   # Storage: pcloud (e.g. ~31 on the list)
   # client_id / client_secret: Enter (rclone defaults)
   # Auth: y → opens pCloud OAuth browser
   # root_folder_id: Enter (root) or target folder ID
   # Edit advanced config: n
   ```
4. **Offsite folder structure:**
   ```bash
   rclone mkdir pcloud:homelab-backups
   rclone mkdir pcloud:homelab-backups/vzdump
   rclone mkdir pcloud:homelab-backups/postgres
   rclone mkdir pcloud:homelab-backups/homeassistant
   rclone mkdir pcloud:homelab-backups/opnsense
   rclone mkdir pcloud:homelab-backups/repo-zip
   ```
5. **Verification (without printing tokens):**
   ```bash
   rclone listremotes          # expected: pcloud:
   rclone lsd pcloud:          # root directory list
   rclone lsd pcloud:homelab-backups
   # upload test (small file):
   echo ok > /tmp/rclone-test.txt
   rclone copy /tmp/rclone-test.txt pcloud:homelab-backups/
   rclone ls pcloud:homelab-backups/rclone-test.txt
   rclone delete pcloud:homelab-backups/rclone-test.txt
   rm /tmp/rclone-test.txt
   ```
6. **Bitwarden:** Secure Note `homelab/RCLONE_CONFIG/prod` — note "OAuth token in ~/.config/rclone/rclone.conf section [pcloud]"; **do not** paste the full file into repo/chat.
7. **GitHub (F5, not now):** after NAS VM deploy and backup scripts:
   ```bash
   # on host with working rclone (ubuntu-nas or prod runner):
   gh secret set RCLONE_CONFIG --env prod --body "$(base64 -w0 ~/.config/rclone/rclone.conf)"
   unset RCLONE_CONFIG
   ```
   In `docs/secrets-inventory.md` (F0-10): add `RCLONE_CONFIG` | prod | date.

**Definition of done:**

- [x] pCloud account — **500 GB free** ✅
- [ ] Remote **`pcloud`** in `rclone.conf`, OAuth OK
- [ ] Folder **`homelab-backups/`** (+ DR subfolders) exists on pCloud
- [ ] `rclone lsd pcloud:homelab-backups` works
- [ ] Token/description in Bitwarden
- [ ] `RCLONE_CONFIG` in GH env prod — **F5** (does not block closing A9 on account/remote)

**Blockers (2026-06-11):** no `pcloud` remote in rclone — requires interactive `rclone config` (OAuth in browser).

---

## F0-04e — Bitwarden vault + 2FA (A10)

**Goal:** personal vault ready for v2 procedure: **generate locally → Bitwarden → `gh secret set`** (F1+). Blocks **F0-06** (backup before deletion) and **F0→F1** gate.

**Dependencies:** none (do **before** F0-06 and F0-07 if you do not have a vault yet)

**Architecture decision (plan B15):** **Bitwarden Cloud** — not Vaultwarden, not legacy `BW_*` in GitHub (removed in A0).

**Architecture (v2 plan):**

| Item | Target value |
|------|--------------|
| **Product** | [Bitwarden Cloud](https://bitwarden.com/) (Free sufficient) |
| **2FA** | **Required** — TOTP (app) or hardware key; recovery codes stored offline |
| **Vault folder** | **`homelab`** — one folder/collection for all project entries |
| **Entry naming** | **`homelab/<NAME>/<env>`** — `<NAME>` = GH secret/variable name (e.g. `POSTGRES_PASSWORD`); `<env>` = `dev` \| `prod` \| `repo` \| `local` |
| **Entry type** | **Secure Note** for text secrets; **Login** for user+pass; **attachment** for certs/SSH keys |
| **Tags** | `homelab-v2` (new); `legacy-pre-v2` (pre-greenfield copies — F0-06) |
| **Note fields (recommended)** | creation date, rotation date, related app, GH secret name |
| **GH legacy `BW_*`** | **Do not** restore — that was CI vault access; v2 = manual procedure from laptop |

**Folder layout / example entries:**

```
homelab/                          ← Bitwarden folder
├── TF_API_TOKEN/prod             ← Secure Note (F0-04c / F1)
├── POSTGRES_PASSWORD/dev         ← F1
├── POSTGRES_PASSWORD/prod
├── PROXMOX_API_TOKEN_SECRET/dev
├── PROXMOX_API_TOKEN_SECRET/prod
├── RCLONE_CONFIG/prod            ← OAuth description; full file local only (F0-04d / F5)
├── SSL_CERT/prod                 ← attachment (legacy backup, F0-06)
├── SSL_CHAIN/prod
├── SSL_PKEY/prod
└── UBUNTU_DOCKER_SSH_PRIV/local  ← private key: attachment or ~/.ssh/ only + pub in GH variable
```

**Relation to F0-06:** F0-06 requires an **existing** vault (this gate). For each legacy secret from F0-05: copy to `homelab/<NAME>/<env>` with tag `legacy-pre-v2` **or** consciously mark "generate new in F1". Without A10 there is no sensible place for backup before F0-07 (already done — values only in GH were **irrecoverably** lost).

**Verification (2026-06-11):**

| Item | Status |
|------|--------|
| **Product** | Bitwarden **Password Manager** (not Secrets Manager) |
| Account + 2FA | user confirmed ✅ |
| Folder **`homelab`** | user confirmed ✅ |
| Entry **`TF_API_TOKEN/prod`** | user confirmed ✅ |
| `bw` CLI | optional — not required for gate |
| `gh` — no `BW_*` | A0 ✅ |

**Manual steps (one-time):**

1. **Account:** [bitwarden.com](https://bitwarden.com/) — register or log in to existing account.
2. **2FA:** Settings → Two-step Login → Authenticator App (TOTP) **or** Security Key; save **recovery codes** (Secure Note outside vault or printout).
3. **Folder:** in vault create folder **`homelab`** (Collections → New Collection if using an organization).
4. **Test entry:** Secure Note `homelab/TEST/dev` with random value (`openssl rand -base64 8`) — then delete test.
5. **Optional CLI** (convenient for rotation; **not** required for gate):
   ```bash
   # install (one of):
   npm install -g @bitwarden/cli
   # alternative: https://bitwarden.com/download/#downloads-cli

   bw login          # email master password — interactive
   bw unlock         # → session key in memory (DO NOT log/paste session key)
   bw status         # expected: "status":"unlocked" or "locked" + "url":"https://vault.bitwarden.com"
   bw list folders   # should show homelab folder after creating in UI
   bw lock
   ```
6. **After gate:** first real entries in **F0-06** (legacy) and **F1** (`gh secret set`).

**Definition of done:**

- [x] Bitwarden Cloud account + **2FA enabled**
- [x] Folder **`homelab`** created
- [x] Entry **`TF_API_TOKEN/prod`** (Secure Note)
- [x] Schema **`homelab/<NAME>/<env>`** — in use
- [ ] (Optional) `bw login` + `bw status` OK
- [x] A10 gate closed (user 2026-06-11)

**Blockers (2026-06-11):** no `bw` CLI; no local Bitwarden config; vault/2FA require interactive user login — agent cannot confirm access without secrets.

---

## F0-05 — Legacy secrets/variables audit

**Goal:** full list of old credentials before deletion (plan: F0 cleanup).

**Dependencies:** F0-04

**Commands:**

```bash
gh secret list
gh secret list --env dev
gh secret list --env prod
gh variable list --env dev
gh variable list --env prod
```

**Expected legacy list (verify against audit):**

| Name | Type | Env |
|------|------|-----|
| `POSTGRES_PASSWORD` | secret | dev, prod |
| `PROXMOX_API_TOKEN_SECRET` | secret | dev, prod |
| `PROXMOX_SSH_PASSWORD` | secret | dev, prod |
| `UBUNTU_DOCKER_PASSWORD` | secret | dev, prod |
| `UBUNTU_DOCKER_SSH_PRIV` | secret | dev, prod |
| `SSL_CERT`, `SSL_CHAIN`, `SSL_PKEY` | secret | prod |
| `PROXMOX_API_URL` | variable | dev, prod |
| `PROXMOX_API_TOKEN_ID` | variable | dev, prod |
| `PROXMOX_SSH_USERNAME` | variable | dev, prod |
| `UBUNTU_DOCKER_SSH_PUB` | variable | dev, prod |
| `BW_ACCESS_TOKEN`, `BW_CLIENTID`, `BW_CLIENTSECRET` | secret | repo-level |

**Definition of done:**

- [x] Audit results recorded (2026-06-11 — A0; repo: 3× BW_*, dev: 5 secrets + 4 vars, prod: 8 secrets + 4 vars)
- [x] Known what to delete in F0-07

---

## F0-06 — Bitwarden backup before deletion

**Goal:** do not lose values that GitHub will no longer show.

**Dependencies:** F0-05, **F0-04e** (A10 — vault must exist before backup)

**Context:** F0-07 already deleted legacy GH secrets (A0). Values that existed **only** in GitHub are **UNRECOVERABLE** — GitHub Secrets are write-only and cannot be read back after deletion.

**Steps:**

1. For each secret from F0-05: if the value was only in GitHub — **cannot be recovered**; if you have it elsewhere, record it in Bitwarden.
2. SSL certs (prod): export / copy to Bitwarden (attachment) if still needed.
3. Tag Bitwarden entries as `legacy-pre-v2` vs future `homelab-v2`.

**Legacy secret decisions (2026-06-29):**

| Secret | Decision | Notes |
|--------|----------|-------|
| POSTGRES_PASSWORD (dev/prod) | Generate new in F1 | GH value lost |
| PROXMOX_* (dev/prod) | Generate new in F1 | GH value lost |
| UBUNTU_DOCKER_* (dev/prod) | Generate new in F1 | GH value lost |
| SSL_CERT/CHAIN/PKEY (prod) | Generate new in F1 or N/A | Unless user has copy elsewhere |
| BW_* (repo) | Do not restore | v2 uses manual Bitwarden workflow |
| TF_API_TOKEN/prod | In Bitwarden ✅ | user confirmed |

**Definition of done:**

- [x] Decision per secret: "have copy" / "generate new in F1"
- [x] No planned deletion without a conscious decision

---

## F0-07 — Remove legacy secrets/variables

**Goal:** clean GitHub Environments for v2.

**Dependencies:** F0-06

**Commands (repeat for each name from audit):**

```bash
gh secret delete NAME --env dev
gh secret delete NAME --env prod
gh variable delete NAME --env dev
gh variable delete NAME --env prod
gh secret delete NAME    # repo-level, without --env
```

**Definition of done:**

- [x] `gh secret list --env dev` — empty (2026-06-11)
- [x] `gh secret list --env prod` — empty (2026-06-11)
- [x] Repo-level legacy (`BW_*`) removed

**Note:** new v2 secrets per `docs/secrets-inventory.md` — in **F1** only.

---

## F0-08 — Self-hosted runner (legacy)

**Goal:** remove old runner if it was attached to the repo.

**Dependencies:** F0-04

**Steps:**

1. GitHub → **homelab** → Settings → Actions → Runners
2. Remove self-hosted runner (if exists)

**Definition of done:**

- [x] No self-hosted runners (2026-06-11 — API returned empty list)

---

## F0-09 — Create `homelab-v2` branch

**Goal:** separate greenfield from `main` / `dev`.

**Dependencies:** F0-04, F0-07 (recommended: cleanup before first v2 push)

**Steps:**

```bash
git fetch origin
git checkout main
git pull
git checkout -b homelab-v2
git push -u origin homelab-v2
```

**Definition of done:**

- [x] Branch `homelab-v2` exists on `origin` (2026-06-11, `15102bd`)
- [x] Working locally on `homelab-v2` (tracking `origin/homelab-v2`)

**Optional (A7):** env `dev` branch policy → `homelab-v2` only (GitHub API, after F0-09).

---

## F0-10 — Commit docs on `homelab-v2`

**Goal:** F0 documentation (this file, later `secrets-inventory.md`) on the v2 working branch.

**Dependencies:** F0-09

**Steps:**

```bash
git checkout homelab-v2
git add docs/manual-setup.md
git commit -m "docs: manual setup checklist for F0 sprint"
git push
```

**Definition of done:**

- [x] `docs/manual-setup.md`, `docs/apps-sources.md`, `docs/secrets-inventory.md` on `homelab-v2` remote (2026-06-11, `4d0ab71`)

---

## F0-11 — Bitwarden preparation

**Goal:** alias checklist for **A10** — details in **[F0-04e](#f0-04e--bitwarden-vault--2fa-a10)**.

**Dependencies:** none

**Definition of done:** same as F0-04e — vault accessible, 2FA, `homelab` folder, naming schema.

---

## F0-12 — F0 gate — final verification

**Goal:** confirm readiness for **F1** (pipeline, dev VM, new secrets).

**Dependencies:** F0-01 … F0-11

**Gate checklist:**

- [x] F0-01 … F0-11 complete (or F0-08 N/A; F0-04d `[~]` deferred to F5)
- [x] Plan: 🔴 questions **B1–B7** closed (or consciously deferred with justification)
- [x] Plan: checklist **A** — **A0 ✅**, **A7 ✅**, **A8 ✅**, **A10 ✅**
- [x] `libvirtd` + `default` network — OK (F0-03)
- [x] GitHub dev/prod — no legacy secrets (A0 2026-06-11)
- [x] GitHub Environments — prod approval + branch `main` (A7 2026-06-11)
- [x] Terraform Cloud — org `dkhomelabserver`, workspace `homelab`, `terraform login` (A8 ✅)
- [x] Branch `homelab-v2` — on `origin` ✅ (F0-09); docs in F0-10

**F0 gate closed:** 2026-06-11 — **F1 may start** (GHA pipelines, dev VM, new `gh secret set`, TFC execution **Local** before prod apply).

**After gate:** start **F1** sprint (GitHub Actions, dev VM, `README` skeleton, new secrets).

---

## Reference — required tools

| Tool | Purpose | Install |
|------|---------|---------|
| `git` | Repo, branches | `sudo apt install git` |
| `gh` | Secrets, PR, Actions | `sudo apt install gh` |
| `terraform` | Prod infra (TFC) | [HashiCorp install](https://developer.hashicorp.com/terraform/install) |
| `ansible` | VM configuration | `sudo apt install ansible` |
| `ansible-lint` | CI validate | `pipx install ansible-lint` |
| `docker` + compose | Local test (optional) | [Docker Engine](https://docs.docker.com/engine/install/debian/) |
| `openssl` | Password generation | `sudo apt install openssl` |
| `virsh`, `virt-install` | Dev VM (libvirt) | `libvirt-clients`, `virtinst` |
| `rclone` | Offsite backup → pCloud (A9/F5) | `sudo apt install rclone` |
| `bw` (optional) | Bitwarden CLI — secret rotation (A10) | `npm install -g @bitwarden/cli` |

---

## Reference — new secret procedure (F1+)

```bash
SECRET=$(openssl rand -base64 32)
# → paste into Bitwarden, then:
gh secret set NAME --env dev --body "$SECRET"
unset SECRET
# → record name in docs/secrets-inventory.md (no value)
```

---

## Reference — A15 Storage sizing (F3/F5)

**Gate A15:** backup retention + library GB estimates — blocks **F3** (TF mount/sizing) and **F5** (backup jobs). **Status: [x] ✅ 2026-06-11**

### Decisions (closed)

| Item | Value |
|------|-------|
| **Local retention** | **2 newest** copies per stream; on 3rd backup delete oldest |
| **Streams** | `vzdump` (apps + NAS VM), `pg_dump`, HA `.tar`, OPNsense config |
| **B6 storage** | SA500 → NFS (Immich/media); Purple → backups; Postgres/cache local on apps VM |
| **Offsite (homelab rclone)** | **DR only:** vzdump, configs, `pg_dump`, **git repo zip** — **NOT** full media libraries |
| **Media offsite** | Already on pCloud separately (outside homelab rclone) |

### Prod caps (user 2026-06-11)

| Media | Prod cap | Current (before import) |
|-------|----------|-------------------------|
| Immich (photos) | **60 GB** → 69 GB with thumbnails | 35 GB |
| Music (Navidrome) | **150 GB** | 58 GB |
| Video (Jellyfin) | **400 GB** | 90 GB |

**Dev (libvirt VM):** a few **MB** per library — functional test only, not prod sizing.

### Hardware (v2 plan)

| Disk | Capacity | Role |
|------|----------|------|
| System SSD | 256 GB | Proxmox + root VM (`ubuntu-apps`, `ubuntu-nas`) |
| **SA500** | **2 TB** | Hot: Immich, music (Navidrome), Jellyfin/Syncthing (NFS) |
| **Purple** | **4 TB** | Local backups (vzdump, dumps) — **not** full SA500 copy |

### Estimate table (prod)

| Category | Location | Formula | Value | % of disk |
|----------|----------|---------|-------|-----------|
| Immich (with thumbnails) | SA500 | `60 × 1.15` | **69 GB** | ~3% / 2 TB |
| Music (Navidrome) | SA500 | cap | **150 GB** | +8% |
| Video (Jellyfin) | SA500 | cap | **400 GB** | +20% |
| Syncthing (opt.) | SA500 | `SYNC_GB` | **20 GB** | +1% |
| NFS buffer | SA500 | fixed | **100 GB** | +5% |
| **Σ SA500** | **2 TB** | sum | **739 GB** | **~37%** |
| Postgres + Docker (P0) | SSD apps VM | `30 + DB_GB` | **~40 GB** | local |
| vzdump apps × 2 | Purple | `2 × ~45 GB` | **~90 GB** | ~2% / 4 TB |
| vzdump NAS × 2 (root only) | Purple | `2 × ~15 GB` | **~30 GB** | +1% |
| pg_dump × 2 | Purple | `2 × PG_GB` | **~10 GB** | <1% |
| HA + OPNsense × 2 | Purple | `2 × ~1 GB` | **~2 GB** | <1% |
| Purple buffer | Purple | 20% | **~26 GB** | +1% |
| **Σ Purple (DR)** | **4 TB** | sum | **~158 GB** | **~4%** |
| pCloud (homelab DR only) × 2 | pCloud | like Purple + repo zip | **~160 GB** | ✅ **500 GB free** (user 2026-06-11) |

**Formulas:**

```
Σ_SA500 = (60 × 1.15) + 150 + 400 + 20 + 100 = 739 GB
Σ_Purple ≈ 158 GB  (2× DR retention; F5 will verify after first vzdump)
Σ_pCloud ≈ 160 GB  (backup-only; no media — media already on pCloud separately)
```

### Alert thresholds

| Condition | Action |
|-----------|--------|
| **Σ SA500 > 1.5 TB** | Plan archive or larger disk |
| **Immich > 500 GB** | Earlier SA500 upgrade or archive tier |
| **pCloud free < ~200 GB** | Monitor usage; homelab DR ~160 GB + media separately |
| **Σ SA500 < 800 GB** | Current SA500 2 TB sufficient for years at normal growth |

### Definition of done (A15)

- [x] Retention: 2 newest copies per stream (local)
- [x] Prod caps: Immich 60 GB, music 150 GB, video 400 GB
- [x] Calculate Σ SA500 = **739 GB** — fits on 2 TB
- [x] Purple DR **~158 GB**; pCloud homelab DR **~160 GB** (no media); **500 GB free** on pCloud ✅
- [x] Dev: few MB per library (test only)
- [x] Check A15 in plan as `[x]`

**Status (2026-06-11):** `[x]` ✅

---

## Reference — A16 application sources (F4/F6)

**Gate A16:** GitHub / source verification per app — **[x] ✅ 2026-06-11 (20/20)**  
Full table: [`docs/apps-sources.md`](apps-sources.md)

---

## Reference — troubleshooting

| Problem | Solution |
|---------|----------|
| `virsh: failed to connect` | `sudo systemctl start libvirtd`; `libvirt` group |
| `network default not found` | `sudo apt install libvirt-daemon-config-network` |
| `gh: Resource not accessible` | `gh auth refresh -s repo,workflow` |
| Forgot a secret | GitHub will not show it — Bitwarden or new secret in F1 |

---

*F0 sprint reference document. Last updated: 2026-06-29 (F0-06 closed, docs translated to English).*
