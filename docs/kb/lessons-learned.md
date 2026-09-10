# Lessons learned

Append-only. If a deploy or test hits a non-obvious failure, add a row **in the same change that fixes it**.

Template: *date · phase · symptom · cause · fix · prevent / code pointer*.

| Date | Phase | Symptom | Cause | Fix | Prevent |
|------|-------|---------|-------|-----|---------|
| 2026-09-10 | F3/F4 | Immich ML crash, `Illegal instruction` | Guest CPU `kvm64`/`qemu64` — NumPy needs x86-64-v2 | `cpu_type = "host"` in TF | `terraform/environments/*/terraform.tfvars` |
| 2026-09-10 | F7 | pgAdmin refuses to start / create user | Email `@homelab.local` — `.local` is a reserved TLD | One real mailbox per env (`environment_email` in identities) | `config/identities.yml` · pgAdmin note in `services.yml` |
| 2026-09-10 | F4 | BentoPDF connection reset | Container listens on **8080**, not 80 | `8085:8080` | `compose/core/docker-compose.yml` bentopdf |
| 2026-09-10 | F4 | `immich-postgres` crash loop during geodata init | `mem_limit: 512m` OOM | 768m minimum | compose Immich postgres service |
| 2026-09-10 | F3 | `docker compose` not found on guest | Ubuntu cloud image has no v2 plugin | Install `docker-compose-v2` in Ansible | `deploy-core.yml` |
| 2026-09-10 | F4 | `docker compose` cannot read `.env` | File was `root:root` `0600` | `ubuntu-dev:docker` `0640` | `deploy-core.yml` |
| 2026-09-10 | F4 | Portainer “timed out for security purposes” | First admin must exist shortly after first start | Bootstrap immediately | `utils/bootstrap/portainer.sh` |
| 2026-09-10 | F4 | Grocery ports missing in Portainer UI | `network_mode: host` hides published ports | Bridge + `8101:8101` | `compose/grocery/` |
| 2026-09-10 | F7 | Authelia login works then drops / first-factor KO on IP | Cookie domain `homelab.local` ≠ raw IP | `/etc/hosts` + `--resolve authelia.homelab.local` | `utils/bootstrap/authelia.sh` |
| 2026-09-10 | F3 | TF API 404 / wrong node | Nested PVE hostname is `dev`, not `pve` | `proxmox_node_name = "dev"` | `environments/dev/terraform.tfvars` |
| 2026-09-10 | F3 | Local `terraform apply` refuses to run | `cloud {}` in `cloud.tf` wants TFC | `utils/dev-apply-local.sh` moves it aside | that helper |
| 2026-09-10 | F7-C | CI never starts | Runner `svc.sh` needs root | `sudo ./svc.sh start` | `troubleshooting.md` |
| 2026-09-10 | F7 | `immich-admin reset-admin-password` hangs | CLI is an inquirer prompt; a pipe is not a TTY | pexpect | `utils/bootstrap/immich.sh` · `python3-pexpect` |
| 2026-09-10 | F7 | Portainer helper reset, still cannot log in | Helper prints `login: \`password\`` — old sed missed it | Parse that form, then API-set declared secret | `utils/bootstrap/portainer.sh` |
| 2026-09-10 | F7 | Homarr bootstrap hung; password visible in `ps` | `homarr-cli` blocks; password was on `docker exec` argv | Skip CLI; rotate leaked secret; never put PW on host argv | `utils/bootstrap/homarr.sh` |
| 2026-09-10 | F7-C | TF plan wants to **destroy** apps VM | `openssl passwd -6` new salt every run → cloud-init “drift” | Deterministic SHA256 salt; `ignore_changes = [initialization]` | `dev-apply-local.sh` · `terraform/main.tf` |
| 2026-09-10 | F7-C | Infra test FAIL while guest already resized | Local tfstate still had 2048/qemu64/16G | Patch state to match live; test FAILs only on VM replace | `tests/infra/run.sh` |
| 2026-09-10 | F7 | Syncthing GUI password set, basic auth still 401 | Current Syncthing uses session login, not HTTP basic | `POST /rest/noauth/auth/password` | `utils/bootstrap/syncthing.sh` |
| 2026-09-10 | F7 | Navidrome `user edit` “inappropriate ioctl” | `--set-password` needs a TTY | `docker exec -t` + pexpect | `utils/bootstrap/navidrome.sh` |
| 2026-09-10 | F7 | Jellyfin login failed for `admin` | First wizard created user **`root`** | Rename + PBKDF2 hash, or wipe `jellyfin_config` on DEV | `docs/kb/apps/jellyfin.md` |
| 2026-09-10 | F4 | pgAdmin / Immich OOM under load | Limits too low for workers + geodata | pgAdmin 512m, Immich server 1536m, ML 384m | compose mem_limits |
