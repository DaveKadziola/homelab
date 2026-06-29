# Ręczny setup laptopa — sprint F0

> **Status:** dokument referencyjny do **planowania i sprintu F0**.  
> **Nie wykonuj teraz** — odhaczaj kroki w trakcie sprintu F0, przed startem F1.  
> **Powiązane:** plan greenfield v2, gate F0→F1, [`README.md`](../README.md) (linkuje tutaj w sekcji „Wymagania wstępne”).

**Repo:** [DaveKadziola/homelab](https://github.com/DaveKadziola/homelab)  
**Gałąź docelowa pracy:** `homelab-v2` (od `main`)

---

## Sprint F0 — przegląd zadań

| ID | Zadanie | Sprint | Blokuje F1? | Status |
|----|---------|--------|-------------|--------|
| [F0-01](#f0-01--audyt-narzędzi-na-laptopie) | Audyt narzędzi na laptopie | F0 | tak | [x] |
| [F0-02](#f0-02--instalacja-brakujących-pakietów) | Instalacja brakujących pakietów | F0 | tak | [x] |
| [F0-03](#f0-03--grupy-użytkownika-i-libvirt) | Grupy użytkownika + libvirt | F0 | tak | [x] |
| [F0-04](#f0-04--github-cli-i-dostęp-do-repo) | GitHub CLI i dostęp do repo | F0 | tak | [x] |
| [F0-04b](#f0-04b--github-environments-devprod-a7) | GitHub Environments dev/prod (A7) | F0 | tak | [x] |
| [F0-04c](#f0-04c--terraform-cloud-workspace-a8) | Terraform Cloud workspace (A8) | F0 | tak | [x] |
| [F0-04d](#f0-04d--pcloud--rclone-auth-a9) | pCloud + rclone auth (A9) | F0 | nie* | [~] |
| [F0-04e](#f0-04e--bitwarden-vault--2fa-a10) | Bitwarden vault + 2FA (A10) | F0 | tak | [x] |
| [F0-05](#f0-05--audyt-legacy-secretsvariables) | Audyt legacy secrets/variables | F0 | tak | [x] |
| [F0-06](#f0-06--backup-w-bitwarden-przed-kasowaniem) | Backup w Bitwarden przed kasowaniem | F0 | tak | [ ] |
| [F0-07](#f0-07--usunięcie-legacy-secretsvariables) | Usunięcie legacy secrets/variables | F0 | tak | [x] |
| [F0-08](#f0-08--self-hosted-runner-legacy) | Self-hosted runner (legacy) | F0 | nie* | [x] N/A |
| [F0-09](#f0-09--utworzenie-gałęzi-homelab-v2) | Utworzenie gałęzi `homelab-v2` | F0 | tak | [x] |
| [F0-10](#f0-10--commit-docs-na-homelab-v2) | Commit `docs/` na `homelab-v2` | F0 | zalecane | [x] |
| [F0-11](#f0-11--przygotowanie-bitwarden) | Przygotowanie Bitwarden | F0 | tak | [x] |
| [F0-12](#f0-12--gate-f0--weryfikacja-końcowa) | Gate F0 — weryfikacja końcowa | F0 | tak | [ ] |

\* F0-08 tylko jeśli runner istnieje w repo.  
\* F0-04d blokuje **F5** (backup jobs), nie gate F0→F1 — można odłożyć do sprintu F5, ale konto pCloud warto założyć wcześniej.

**Poza F0 (F1):** utworzenie dev VM, nowe `gh secret set`, pipeline GitHub Actions — patrz plan, faza F1.

---

## F0-01 — Audyt narzędzi na laptopie

**Cel:** wiedzieć, co już jest zainstalowane, zanim cokolwiek doinstalujesz.

**Komendy:**

```bash
for cmd in git gh terraform ansible ansible-playbook ansible-lint docker virsh virt-install openssl ssh-keygen; do
  printf '%-20s' "$cmd:"; command -v "$cmd" || echo "BRAK"
done
docker compose version 2>/dev/null || echo "docker compose: BRAK"
groups
```

**Definition of done:**

- [x] Lista narzędzi OK / BRAK zapisana (2026-06-11 — poniżej)
- [x] Wiadomo, które kroki F0-02 są potrzebne → **ansible-lint**, **libvirtd**, sieć `default`

**Wynik audytu (2026-06-11):**

| Narzędzie | Stan | Wersja / uwagi |
|-----------|------|----------------|
| `git` | OK | 2.47.3 |
| `gh` | OK | 2.46.0 |
| `terraform` | OK | 1.15.6 |
| `ansible` | OK | core 2.19.4 |
| `ansible-playbook` | OK | `/usr/bin/ansible-playbook` |
| `ansible-lint` | **BRAK** | → F0-02 (`pipx install ansible-lint`) |
| `docker` | OK | |
| `docker compose` | OK | v5.1.4 |
| `virsh` | OK | 11.3.0 |
| `virt-install` | OK | |
| `openssl` | OK | |
| `ssh-keygen` | OK | |
| `rclone` | OK | 1.60.1-DEV |
| `bw` | BRAK | opcjonalnie (A10 gate zamknięty bez CLI) |

**Grupy:** `kvm`, `libvirt`, `docker` — OK

**Libvirt:** `libvirtd` = **active** ✅; sieć `default` = **active** + autostart ✅ (2026-06-11, `qemu:///system`)

**Uwaga:** używaj `virsh -c qemu:///system` jeśli zwykłe `virsh net-list` zwraca pustą listę (połączenie sesji vs system).

**Oczekiwany stan docelowy (F1):** wszystkie pozycje z [tabeli narzędzi](#referencja--wymagane-narzędzia) obecne.

---

## F0-02 — Instalacja brakujących pakietów

**Cel:** uzupełnić braki z F0-01.

**Zależności:** F0-01

**Debian 13 — przykład:**

```bash
sudo apt update
sudo apt install -y git gh ansible openssl openssh-client \
  libvirt-clients virtinst qemu-kvm libvirt-daemon-system

# ansible-lint — jeśli brak w apt:
sudo apt install -y pipx
pipx ensurepath
pipx install ansible-lint
```

**Weryfikacja:**

```bash
git --version && gh --version && terraform version && ansible --version
ansible-lint --version && docker compose version && virsh --version
```

**Definition of done:**

- [x] Wszystkie wymagane narzędzia zwracają wersję (2026-06-11)
- [x] `ansible-lint` — zainstalowany via `pipx` (26.4.0); upewnij się że `~/.local/bin` jest w `PATH`

---

## F0-03 — Grupy użytkownika i libvirt

**Cel:** libvirt i Docker działają bez zbędnego sudo; sieć `default` gotowa pod dev VM (samą VM tworzysz w **F1**).

**Zależności:** F0-02

**Kroki:**

```bash
# 1. Grupy (jeśli brak w groups)
sudo usermod -aG libvirt,kvm,docker "$USER"
# → wyloguj / zaloguj lub: newgrp libvirt

# 2. Demon libvirt
sudo systemctl enable --now libvirtd
systemctl is-active libvirtd   # oczekiwane: active

# 3. Sieć default
virsh net-list --all
sudo virsh net-start default
sudo virsh net-autostart default
# alternatywa: ./utils/start_qemu_default_net
```

**Definition of done:**

- [x] Użytkownik w grupach `libvirt`, `kvm`, `docker` (F0-01)
- [x] `libvirtd` = **active** (2026-06-11)
- [x] Sieć `default` = **active** + **autostart** (`virsh -c qemu:///system net-list --all`)
- [x] `virsh -c qemu:///system list --all` działa bez błędu

---

## F0-04 — GitHub CLI i dostęp do repo

**Cel:** `gh` zalogowany z uprawnieniami do secrets i workflow.

**Zależności:** F0-02

**Kroki:**

```bash
gh auth login
gh auth status
# wymagane scope: repo, workflow

cd /ścieżka/do/homelab
git fetch origin
git checkout main
git pull
```

**Definition of done:**

- [x] `gh auth status` — **DaveKadziola**, scope `repo` + `workflow` (2026-06-11)
- [x] `git fetch origin` OK
- [x] Gałąź lokalna: **`homelab-v2`** (tracking `origin/homelab-v2`, `15102bd`); `docs/` **untracked** → F0-10

**Weryfikacja (2026-06-11):**

| Element | Stan |
|---------|------|
| `gh auth` | OK — `repo`, `workflow` |
| `origin/main` | dostępny (`15102bd`) |
| `origin/homelab-v2` | **OK** ✅ F0-09 |
| Lokalna gałąź | `dev`; `?? docs/` |


---

## F0-04b — GitHub Environments dev/prod (A7)

**Cel:** środowiska `dev` i `prod` gotowe pod CI v2 — approval na prod, gałąź deploy prod = `main`.

**Zależności:** F0-04, F0-07 (zalecane: puste env przed pierwszym secretem v2)

**Weryfikacja (2026-06-11):**

| Element | Stan |
|---------|------|
| Repo | `DaveKadziola/homelab`, **public**, default branch **`main`** |
| `gh auth` | OK — scope `repo`, `workflow` |
| Environment `dev` | istnieje, secrets puste |
| Environment `prod` | istnieje, secrets puste |
| Prod — required reviewer | `DaveKadziola` |
| Prod — deployment branches | tylko **`main`** (plan mówi `master` — w repo używamy `main`) |
| Actions | włączone, `allowed_actions: all` |
| `gh secret set --env dev` | OK (test usunięty) |

**Prod — approval + branch policy (jednorazowo, przez API):**

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

**Po F0-09** (gałąź `homelab-v2`): opcjonalnie ograniczyć deploy **dev** do gałęzi `homelab-v2` — analogicznie `deployment-branch-policies` na env `dev`.

**Definition of done:**

- [x] Environments `dev` + `prod` istnieją
- [x] Prod wymaga approval przed deployem
- [x] Prod akceptuje deploy tylko z gałęzi `main`
- [x] `gh secret set --env dev` działa (secrets v2 dopiero w F1)

---

## F0-04c — Terraform Cloud workspace (A8)

**Cel:** konto HCP Terraform (Terraform Cloud) + workspace **prod** na pusty state v2 — **bez** importu legacy tfstate.

**Zależności:** F0-04 (konto GitHub OK); F0-07 zalecane (brak kolizji secretów w GH)

**Architektura (plan v2):**

| Element | Wartość docelowa |
|---------|------------------|
| **Org TFC** | **`dkhomelabserver`** (decyzja 2026-06-11) |
| **Workspace prod** | **`homelab`** (org `dkhomelabserver`) |
| **Workspace dev** | **brak** — dev TF na laptopie (libvirt), lokalny state; TFC **tylko prod** |
| **Backend w repo** | `cloud { ... }` w `terraform/versions.tf` — dopiero w **F1**, nie teraz |
| **GH secret** | `TF_API_TOKEN` → env **prod** (F1); **nie** w repo |

**Weryfikacja (2026-06-11 — bez tokenów użytkownika):**

| Element | Stan |
|---------|------|
| `terraform` CLI | v1.14.6 (`/usr/bin/terraform`) |
| `~/.terraform.d/credentials.tfrc.json` | **OK** (2026-06-11) |
| Workspace **`homelab`** | org `dkhomelabserver`, `resource-count: 0`, auto-apply OFF, execution **remote** (→ Local w F1) |

**Kroki ręczne (jednorazowo):**

1. **Konto:** [app.terraform.io/signup](https://app.terraform.io/signup) — plan **Free** wystarczy (1 org, wiele workspace’ów w limicie free).
2. **Organizacja:** org **`dkhomelabserver`** — już utworzona ✅
3. **Workspace prod:**
   - Nazwa: **`homelab`** — utworzony ✅
   - **Execution mode:** obecnie **remote** → w **F1** ustaw **Local** (apply z self-hosted runnera w LAN)
   - **Terraform version:** ≥ 1.8.0 (repo: `required_version = ">= 1.8.0"`).
   - **Auto apply:** **OFF** (apply tylko przez `infra-apply-prod.yml` + approval GH env prod).
   - **State:** pusty — **nie** importuj starego `terraform.tfstate` z legacy CI.
4. **Token API (User settings → Tokens):**
   ```bash
   terraform login
   # alternatywa: wklej token ręcznie do ~/.terraform.d/credentials.tfrc.json
   ```
   Skopiuj token do Bitwarden (`homelab/TF_API_TOKEN/prod`), potem w **F1**:
   ```bash
   gh secret set TF_API_TOKEN --env prod --body "$TOKEN"
   unset TOKEN
   ```
5. **Weryfikacja po loginie:**
   ```bash
   # org: dkhomelabserver
   curl -s \
     --header "Authorization: Bearer $(python3 -c "import json;print(json.load(open('$HOME/.terraform.d/credentials.tfrc.json'))['credentials']['app.terraform.io']['token'])")" \
     "https://app.terraform.io/api/v2/organizations/dkhomelabserver/workspaces/homelab" \
     | python3 -m json.tool | head -20
   ```
   Oczekiwane: JSON z `"name": "homelab"`, bez `"errors"`.

**Variable Set (opcjonalnie teraz, wymagane przed pierwszym prod apply w F3):**

W TFC utwórz Variable Set przypięty do **`homelab`** — wartości **później** z Bitwarden / `gh secret set` (F1), nie w repo:

| Zmienna TFC | Sensitive | Źródło (F1+) |
|-------------|-----------|--------------|
| `TF_VAR_proxmox_api_url` | nie | GH variable prod |
| `TF_VAR_proxmox_api_token_id` | nie | GH variable prod |
| `TF_VAR_proxmox_api_token_secret` | tak | GH secret prod |
| `TF_VAR_proxmox_ssh_username` | nie | GH variable prod |
| `TF_VAR_proxmox_ssh_password` | tak | GH secret prod |
| `TF_VAR_ubuntu_docker_password` | tak | GH secret prod |
| `TF_VAR_ubuntu_docker_ssh_pub` | nie | GH variable prod |
| `TF_VAR_ssl_*` | tak | GH secret prod (jeśli cert setup w TF) |

**Definition of done:**

- [x] Konto HCP Terraform + org **`dkhomelabserver`**
- [x] Workspace **`homelab`** istnieje, pusty state (2026-06-11)
- [x] `terraform login` OK
- [ ] Token w Bitwarden (`homelab/TF_API_TOKEN/prod`)
- [x] API zwraca workspace — zweryfikowane 2026-06-11
- [ ] `TF_API_TOKEN` w GH env prod — **F1** (nie blokuje zamknięcia A8 konta/workspace)

**Blokery (2026-06-11):** brak `credentials.tfrc.json` / tokena TFC — wymaga interaktywnego `terraform login` lub ręcznego tokenu użytkownika.

---

## F0-04d — pCloud + rclone auth (A9)

**Cel:** konto pCloud + skonfigurowany remote **rclone** do backupów offsite (decyzja **B16**: rclone → pCloud, nie ZeroByte).

**Zależności:** F0-04 (opcjonalnie F0-11 Bitwarden — kopia tokenu OAuth); **nie** blokuje gate F0→F1, blokuje **F5** (NAS backup jobs + sync offsite).

**Architektura (plan v2):**

| Element | Wartość docelowa |
|---------|------------------|
| **Narzędzie** | **rclone** (one-way copy/sync do chmury) |
| **Backend** | pCloud (`type = pcloud`) |
| **Nazwa remote** | **`pcloud`** — używaj konsekwentnie w skryptach i cronach F5 |
| **Ścieżka offsite** | **`homelab-backups/`** na pCloud (root konta lub podfolder) |
| **Podfoldery (F5)** | `vzdump/`, `postgres/`, `homeassistant/`, `opnsense/`, `repo-zip/` — **tylko DR** (bez pełnych bibliotek mediów; multimedia już na pCloud osobno) |
| **Lokalnie (Purple 4 TB)** | Retention **2 najnowsze** backupy (A15); offsite harmonogram — *TBD* w F5 |
| **GH secret** | **`RCLONE_CONFIG`** → env **prod** (F5) — base64 całego `rclone.conf` **lub** tylko sekcji `[pcloud]`; **nie** w repo |
| **GH env dev** | **brak** — dev nie wysyła backupów offsite |

**Weryfikacja (2026-06-11 — bez credentials użytkownika):**

| Element | Stan |
|---------|------|
| `rclone` CLI | v1.60.1-DEV (`/usr/bin/rclone`, pakiet Debian) |
| `~/.config/rclone/rclone.conf` | plik istnieje, **pusty** (0 B) — brak sekcji `[pcloud]` |
| Remote `pcloud` | **nie** — `rclone listremotes` puste |
| Konto pCloud | ✅ aktywne — **500 GB wolne** (user 2026-06-11) |
| `gh secret list` (repo + dev + prod) | puste — brak `RCLONE_*` (A0 ✅) |
| `.github/workflows/force-proxmox-resource-backup.yml` | legacy placeholder (bez rclone) |

**Kroki ręczne (jednorazowo):**

1. **Konto pCloud:** ✅ konto aktywne — **500 GB wolnego** (2026-06-11); homelab DR backup-only **~160 GB** (2× retention, bez mediów) mieści się z dużym marginesem — patrz [A15 Storage sizing](#referencja--a15-storage-sizing-f3f5). **Multimedia (Immich/muzyka/wideo) już backupowane na pCloud osobno** — homelab rclone ich nie duplikuje.
2. **Instalacja rclone** (jeśli brak po F0-01):
   ```bash
   sudo apt update && sudo apt install -y rclone
   rclone version
   ```
3. **Konfiguracja remote (interaktywna — wymaga logowania pCloud):**
   ```bash
   rclone config
   # n) New remote
   # name: pcloud
   # Storage: pcloud (np. numer ~31 na liście)
   # client_id / client_secret: Enter (domyślne rclone)
   # Auth: y → otwiera przeglądarkę OAuth pCloud
   # root_folder_id: Enter (root) lub ID folderu docelowego
   # Edit advanced config: n
   ```
4. **Struktura folderów offsite:**
   ```bash
   rclone mkdir pcloud:homelab-backups
   rclone mkdir pcloud:homelab-backups/vzdump
   rclone mkdir pcloud:homelab-backups/postgres
   rclone mkdir pcloud:homelab-backups/homeassistant
   rclone mkdir pcloud:homelab-backups/opnsense
   rclone mkdir pcloud:homelab-backups/repo-zip
   ```
5. **Weryfikacja (bez wypisywania tokenów):**
   ```bash
   rclone listremotes          # oczekiwane: pcloud:
   rclone lsd pcloud:          # lista katalogów root
   rclone lsd pcloud:homelab-backups
   # test upload (mały plik):
   echo ok > /tmp/rclone-test.txt
   rclone copy /tmp/rclone-test.txt pcloud:homelab-backups/
   rclone ls pcloud:homelab-backups/rclone-test.txt
   rclone delete pcloud:homelab-backups/rclone-test.txt
   rm /tmp/rclone-test.txt
   ```
6. **Bitwarden:** Secure Note `homelab/RCLONE_CONFIG/prod` — opis „OAuth token w ~/.config/rclone/rclone.conf sekcja [pcloud]”; **nie** wklejaj całego pliku do repo/chat.
7. **GitHub (F5, nie teraz):** po deploy NAS VM i skryptach backup:
   ```bash
   # na hoście z działającym rclone (ubuntu-nas lub runner prod):
   gh secret set RCLONE_CONFIG --env prod --body "$(base64 -w0 ~/.config/rclone/rclone.conf)"
   unset RCLONE_CONFIG
   ```
   W `docs/secrets-inventory.md` (F0-10): wpisz `RCLONE_CONFIG` | prod | data.

**Definition of done:**

- [x] Konto pCloud — **500 GB wolne** ✅
- [ ] Remote **`pcloud`** w `rclone.conf`, OAuth OK
- [ ] Folder **`homelab-backups/`** (+ podfoldery DR) istnieje na pCloud
- [ ] `rclone lsd pcloud:homelab-backups` działa
- [ ] Token/opis w Bitwarden
- [ ] `RCLONE_CONFIG` w GH env prod — **F5** (nie blokuje zamknięcia A9 na koncie/remote)

**Blokery (2026-06-11):** brak remote `pcloud` w rclone — wymaga interaktywnego `rclone config` (OAuth w przeglądarce).

---

## F0-04e — Bitwarden vault + 2FA (A10)

**Cel:** osobisty vault gotowy na procedurę v2: **generuj lokalnie → Bitwarden → `gh secret set`** (F1+). Blokuje **F0-06** (backup przed kasowaniem) i gate **F0→F1**.

**Zależności:** brak (wykonaj **przed** F0-06 i F0-07, jeśli jeszcze nie masz vault)

**Decyzja architektury (plan B15):** **Bitwarden Cloud** — nie Vaultwarden, nie legacy `BW_*` w GitHub (usunięte w A0).

**Architektura (plan v2):**

| Element | Wartość docelowa |
|---------|------------------|
| **Produkt** | [Bitwarden Cloud](https://bitwarden.com/) (Free wystarczy) |
| **2FA** | **Wymagane** — TOTP (appka) lub klucz sprzętowy; recovery codes zapisane offline |
| **Folder w vault** | **`homelab`** — jeden folder/collection na wszystkie wpisy projektu |
| **Schemat nazw wpisu** | **`homelab/<NAZWA>/<env>`** — `<NAZWA>` = nazwa GH secret/variable (np. `POSTGRES_PASSWORD`); `<env>` = `dev` \| `prod` \| `repo` \| `local` |
| **Typ wpisu** | **Secure Note** dla secretów tekstowych; **Login** gdy user+pass; **attachment** dla certów/kluczy SSH |
| **Tagi** | `homelab-v2` (nowe); `legacy-pre-v2` (kopie sprzed greenfield — F0-06) |
| **Pola notatki (zalecane)** | data utworzenia, data rotacji, powiązana appka, nazwa GH secret |
| **GH legacy `BW_*`** | **Nie** przywracać — to był dostęp CI do vault; v2 = ręczna procedura z laptopa |

**Schemat folderów / przykłady wpisów:**

```
homelab/                          ← folder Bitwarden
├── TF_API_TOKEN/prod             ← Secure Note (F0-04c / F1)
├── POSTGRES_PASSWORD/dev         ← F1
├── POSTGRES_PASSWORD/prod
├── PROXMOX_API_TOKEN_SECRET/dev
├── PROXMOX_API_TOKEN_SECRET/prod
├── RCLONE_CONFIG/prod            ← opis OAuth; pełny plik tylko lokalnie (F0-04d / F5)
├── SSL_CERT/prod                 ← attachment (legacy backup, F0-06)
├── SSL_CHAIN/prod
├── SSL_PKEY/prod
└── UBUNTU_DOCKER_SSH_PRIV/local  ← private key: attachment lub tylko ~/.ssh/ + pub w GH variable
```

**Relacja do F0-06:** F0-06 wymaga **istniejącego** vault (ten gate). Dla każdego legacy secretu z F0-05: wpisz kopię do `homelab/<NAZWA>/<env>` z tagiem `legacy-pre-v2` **albo** świadomie oznacz „generuję nowy w F1”. Bez A10 nie ma sensownego miejsca na backup przed F0-07 (już wykonane — wartości tylko w GH były **nieodwracalnie** utracone).

**Weryfikacja (2026-06-11):**

| Element | Stan |
|---------|------|
| **Produkt** | Bitwarden **Password Manager** (nie Secrets Manager) |
| Konto + 2FA | user potwierdził ✅ |
| Folder **`homelab`** | user potwierdził ✅ |
| Wpis **`TF_API_TOKEN/prod`** | user potwierdził ✅ |
| `bw` CLI | opcjonalnie — nie wymagane do gate |
| `gh` — brak `BW_*` | A0 ✅ |

**Kroki ręczne (jednorazowo):**

1. **Konto:** [bitwarden.com](https://bitwarden.com/) — rejestracja lub logowanie na istniejące konto.
2. **2FA:** Settings → Two-step Login → Authenticator App (TOTP) **lub** Security Key; zapisz **recovery codes** (Secure Note poza vault lub wydruk).
3. **Folder:** w vault utwórz folder **`homelab`** (Collections → New Collection, jeśli używasz organizacji).
4. **Test wpisu:** Secure Note `homelab/TEST/dev` z losową wartością (`openssl rand -base64 8`) — potem usuń test.
5. **Opcjonalnie CLI** (wygodne przy rotacji; **nie** wymagane do gate):
   ```bash
   # instalacja (jedna z metod):
   npm install -g @bitwarden/cli
   # alternatywa: https://bitwarden.com/download/#downloads-cli

   bw login          # email master password — interaktywne
   bw unlock         # → session key w pamięci (NIE loguj/wklejaj session key)
   bw status         # oczekiwane: "status":"unlocked" lub "locked" + "url":"https://vault.bitwarden.com"
   bw list folders   # powinien pokazać folder homelab po utworzeniu w UI
   bw lock
   ```
6. **Po gate:** pierwsze prawdziwe wpisy w **F0-06** (legacy) i **F1** (`gh secret set`).

**Definition of done:**

- [x] Konto Bitwarden Cloud + **2FA włączone**
- [x] Folder **`homelab`** utworzony
- [x] Wpis **`TF_API_TOKEN/prod`** (Secure Note)
- [x] Schemat **`homelab/<NAZWA>/<env>`** — w użyciu
- [ ] (Opcjonalnie) `bw login` + `bw status` OK
- [x] A10 gate zamknięte (user 2026-06-11)

**Blokery (2026-06-11):** brak `bw` CLI; brak lokalnej konfiguracji Bitwarden; vault/2FA wymagają interaktywnego logowania użytkownika — agent nie może potwierdzić dostępu bez sekretów.

---

## F0-05 — Audyt legacy secrets/variables

**Cel:** pełna lista starych credentials przed kasowaniem (plan: cleanup F0).

**Zależności:** F0-04

**Komendy:**

```bash
gh secret list
gh secret list --env dev
gh secret list --env prod
gh variable list --env dev
gh variable list --env prod
```

**Oczekiwana lista legacy (zweryfikuj z audytem):**

| Nazwa | Typ | Env |
|-------|-----|-----|
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

- [x] Wyniki audytu zapisane (2026-06-11 — A0; repo: 3× BW_*, dev: 5 secrets + 4 vars, prod: 8 secrets + 4 vars)
- [x] Wiadomo, co kasujesz w F0-07

---

## F0-06 — Backup w Bitwarden przed kasowaniem

**Cel:** nie stracić wartości, których GitHub już nie pokaże.

**Zależności:** F0-05, **F0-04e** (A10 — vault musi istnieć przed backupem)

**Kroki:**

1. Dla każdego secretu z F0-05: jeśli wartość jest tylko w GitHub — **nie da się odzyskać**; jeśli masz ją gdzie indziej, wpisz do Bitwarden.
2. Certy SSL (prod): export / kopia w Bitwarden (attachment), jeśli jeszcze potrzebne.
3. Oznacz w Bitwarden wpisy jako `legacy-pre-v2` vs przyszłe `homelab-v2`.

**Definition of done:**

- [ ] Decyzja per secret: „mam kopię” / „generuję nowy w F1”
- [ ] Brak planowanego kasowania bez świadomej decyzji

---

## F0-07 — Usunięcie legacy secrets/variables

**Cel:** czysty GitHub Environments pod v2.

**Zależności:** F0-06

**Komendy (powtórz dla każdej nazwy z audytu):**

```bash
gh secret delete NAZWA --env dev
gh secret delete NAZWA --env prod
gh variable delete NAZWA --env dev
gh variable delete NAZWA --env prod
gh secret delete NAZWA    # repo-level, bez --env
```

**Definition of done:**

- [x] `gh secret list --env dev` — puste (2026-06-11)
- [x] `gh secret list --env prod` — puste (2026-06-11)
- [x] Repo-level legacy (`BW_*`) usunięte

**Uwaga:** nowe sekrety v2 wg `docs/secrets-inventory.md` — dopiero w **F1**.

---

## F0-08 — Self-hosted runner (legacy)

**Cel:** usunąć stary runner, jeśli był podpięty do repo.

**Zależności:** F0-04

**Kroki:**

1. GitHub → **homelab** → Settings → Actions → Runners
2. Usuń self-hosted runner (jeśli istnieje)

**Definition of done:**

- [x] Brak self-hosted runnerów (2026-06-11 — API zwróciło pustą listę)

---

## F0-09 — Utworzenie gałęzi `homelab-v2`

**Cel:** odseparować greenfield od `main` / `dev`.

**Zależności:** F0-04, F0-07 (zalecane: cleanup przed pierwszym pushem v2)

**Kroki:**

```bash
git fetch origin
git checkout main
git pull
git checkout -b homelab-v2
git push -u origin homelab-v2
```

**Definition of done:**

- [x] Gałąź `homelab-v2` istnieje na `origin` (2026-06-11, `15102bd`)
- [x] Lokalnie pracujesz na `homelab-v2` (tracking `origin/homelab-v2`)

**Opcjonalnie (A7):** branch policy env `dev` → tylko `homelab-v2` (GitHub API, po F0-09).

---

## F0-10 — Commit docs na `homelab-v2`

**Cel:** dokumentacja F0 (ten plik, później `secrets-inventory.md`) w gałęzi roboczej v2.

**Zależności:** F0-09

**Kroki:**

```bash
git checkout homelab-v2
git add docs/manual-setup.md
git commit -m "docs: manual setup checklist for F0 sprint"
git push
```

**Definition of done:**

- [x] `docs/manual-setup.md`, `docs/apps-sources.md`, `docs/secrets-inventory.md` na `homelab-v2` w remote (2026-06-11, `4d0ab71`)

---

## F0-11 — Przygotowanie Bitwarden

**Cel:** alias checklisty **A10** — szczegóły w **[F0-04e](#f0-04e--bitwarden-vault--2fa-a10)**.

**Zależności:** brak

**Definition of done:** jak F0-04e — vault dostępny, 2FA, folder `homelab`, schemat nazw.

---

## F0-12 — Gate F0 — weryfikacja końcowa

**Cel:** potwierdzić gotowość do **F1** (pipeline, dev VM, nowe sekrety).

**Zależności:** F0-01 … F0-11

**Checklist gate:**

- [ ] F0-01 … F0-11 ukończone (lub F0-08 N/A)
- [ ] Plan: pytania 🔴 **B1–B7** zamknięte (lub świadomie odroczone z uzasadnieniem)
- [ ] Plan: checklista **A** — **A0 ✅**, **A7 ✅**, **A8 ✅**, **A10 ✅**
- [ ] `libvirtd` + sieć `default` — OK
- [x] GitHub dev/prod — bez legacy secrets (A0 2026-06-11)
- [x] GitHub Environments — approval prod + branch `main` (A7 2026-06-11)
- [x] Terraform Cloud — org `dkhomelabserver`, workspace `homelab`, `terraform login` (A8 ✅)
- [x] Gałąź `homelab-v2` — na `origin` ✅ (F0-09); docs w F0-10

**Po gate:** start sprintu **F1** (GitHub Actions, dev VM, `README` szkielet, nowe secrets).

---

## Referencja — wymagane narzędzia

| Narzędzie | Po co | Instalacja |
|-----------|--------|------------|
| `git` | Repo, gałęzie | `sudo apt install git` |
| `gh` | Secrets, PR, Actions | `sudo apt install gh` |
| `terraform` | Prod infra (TFC) | [HashiCorp install](https://developer.hashicorp.com/terraform/install) |
| `ansible` | Konfiguracja VM | `sudo apt install ansible` |
| `ansible-lint` | CI validate | `pipx install ansible-lint` |
| `docker` + compose | Lokalny test (opcjonalnie) | [Docker Engine](https://docs.docker.com/engine/install/debian/) |
| `openssl` | Generowanie haseł | `sudo apt install openssl` |
| `virsh`, `virt-install` | Dev VM (libvirt) | `libvirt-clients`, `virtinst` |
| `rclone` | Backup offsite → pCloud (A9/F5) | `sudo apt install rclone` |
| `bw` (opcjonalnie) | Bitwarden CLI — rotacja secretów (A10) | `npm install -g @bitwarden/cli` |

---

## Referencja — procedura nowego secretu (F1+)

```bash
SECRET=$(openssl rand -base64 32)
# → wklej do Bitwarden, potem:
gh secret set NAZWA --env dev --body "$SECRET"
unset SECRET
# → wpisz nazwę w docs/secrets-inventory.md (bez wartości)
```

---

## Referencja — A15 Storage sizing (F3/F5)

**Gate A15:** retention backupów + szacunki GB bibliotek — blokuje **F3** (TF mount/sizing) i **F5** (joby backup). **Status: [x] ✅ 2026-06-11**

### Decyzje (zamknięte)

| Element | Wartość |
|---------|---------|
| **Retention lokalny** | **2 najnowsze** kopie per strumień; przy 3. backupie usuń najstarszy |
| **Strumienie** | `vzdump` (apps + NAS VM), `pg_dump`, HA `.tar`, OPNsense config |
| **B6 storage** | SA500 → NFS (Immich/media); Purple → backupy; Postgres/cache lokalnie na apps VM |
| **Offsite (homelab rclone)** | **Tylko DR:** vzdump, configs, `pg_dump`, **git repo zip** — **NIE** pełne biblioteki mediów |
| **Media offsite** | Już na pCloud osobno (poza homelab rclone) |

### Prod caps (użytkownik 2026-06-11)

| Media | Cap prod | Obecnie (przed importem) |
|-------|----------|--------------------------|
| Immich (zdjęcia) | **60 GB** → 69 GB z miniaturami | 35 GB |
| Muzyka (Navidrome) | **150 GB** | 58 GB |
| Wideo (Jellyfin) | **400 GB** | 90 GB |

**Dev (libvirt VM):** po kilka **MB** każdej biblioteki — tylko test funkcjonalny, nie prod sizing.

### Sprzęt (plan v2)

| Dysk | Pojemność | Rola |
|------|-----------|------|
| SSD system | 256 GB | Proxmox + root VM (`ubuntu-apps`, `ubuntu-nas`) |
| **SA500** | **2 TB** | Hot: Immich, muzyka (Navidrome), Jellyfin/Syncthing (NFS) |
| **Purple** | **4 TB** | Backupy lokalne (vzdump, dumps) — **nie** pełna kopia SA500 |

### Tabela szacunków (prod)

| Kategoria | Miejsce | Formuła | Wartość | % z dysku |
|-----------|---------|---------|---------|-----------|
| Immich (z miniaturami) | SA500 | `60 × 1.15` | **69 GB** | ~3% / 2 TB |
| Muzyka (Navidrome) | SA500 | cap | **150 GB** | +8% |
| Wideo (Jellyfin) | SA500 | cap | **400 GB** | +20% |
| Syncthing (opcj.) | SA500 | `SYNC_GB` | **20 GB** | +1% |
| NFS bufor | SA500 | stałe | **100 GB** | +5% |
| **Σ SA500** | **2 TB** | suma | **739 GB** | **~37%** |
| Postgres + Docker (P0) | SSD apps VM | `30 + DB_GB` | **~40 GB** | lokalnie |
| vzdump apps × 2 | Purple | `2 × ~45 GB` | **~90 GB** | ~2% / 4 TB |
| vzdump NAS × 2 (root only) | Purple | `2 × ~15 GB` | **~30 GB** | +1% |
| pg_dump × 2 | Purple | `2 × PG_GB` | **~10 GB** | <1% |
| HA + OPNsense × 2 | Purple | `2 × ~1 GB` | **~2 GB** | <1% |
| Bufor Purple | Purple | 20% | **~26 GB** | +1% |
| **Σ Purple (DR)** | **4 TB** | suma | **~158 GB** | **~4%** |
| pCloud (homelab DR only) × 2 | pCloud | jak Purple + repo zip | **~160 GB** | ✅ **500 GB wolne** (user 2026-06-11) |

**Formuły:**

```
Σ_SA500 = (60 × 1.15) + 150 + 400 + 20 + 100 = 739 GB
Σ_Purple ≈ 158 GB  (2× retention DR; F5 zweryfikuje po pierwszym vzdump)
Σ_pCloud ≈ 160 GB  (backup-only; bez mediów — media już na pCloud osobno)
```

### Progi alarmowe

| Warunek | Akcja |
|---------|-------|
| **Σ SA500 > 1.5 TB** | Planuj archiwum lub większy dysk |
| **Immich > 500 GB** | Wcześniejszy upgrade SA500 lub tier archiwum |
| **pCloud wolne < ~200 GB** | Monitoruj zajętość; homelab DR ~160 GB + media osobno |
| **Σ SA500 < 800 GB** | Obecny SA500 2 TB wystarcza na lata przy normalnym wzroście |

### Definition of done (A15)

- [x] Retention: 2 najnowsze kopie per strumień (lokalnie)
- [x] Prod caps: Immich 60 GB, muzyka 150 GB, wideo 400 GB
- [x] Przelicz Σ SA500 = **739 GB** — mieści się na 2 TB
- [x] Purple DR **~158 GB**; pCloud homelab DR **~160 GB** (bez mediów); **500 GB wolne** na pCloud ✅
- [x] Dev: kilka MB per biblioteka (test only)
- [x] Odhacz A15 w planie na `[x]`

**Status (2026-06-11):** `[x]` ✅

---

## Referencja — A16 źródła aplikacji (F4/F6)

**Gate A16:** weryfikacja GitHub / źródła per app — **[x] ✅ 2026-06-11 (20/20)**  
Pełna tabela: [`docs/apps-sources.md`](apps-sources.md)

---

## Referencja — rozwiązywanie problemów

| Problem | Rozwiązanie |
|---------|-------------|
| `virsh: failed to connect` | `sudo systemctl start libvirtd`; grupa `libvirt` |
| `network default not found` | `sudo apt install libvirt-daemon-config-network` |
| `gh: Resource not accessible` | `gh auth refresh -s repo,workflow` |
| Nie pamiętam secretu | GitHub nie pokaże — Bitwarden lub nowy secret w F1 |

---

*Dokument referencyjny sprintu F0. Ostatnia aktualizacja: 2026-06-11 (A15 ✅, A16 repo verify, F0-04e / A10).*
