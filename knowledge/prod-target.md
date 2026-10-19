Status: verified
Last reviewed: 2026-10-19
Scope: what the prod rollout (F3-F5) creates, from which file, with which settings; open gaps before `terraform apply`

# Prod target - what gets deployed

Every value below comes from the file named in its row. Where the repo and the live system disagree,
the row says so and the gap is listed at the end. Read with `docs/network.md` (addresses, firewall)
and `knowledge/rebuild.md` (order of steps).

## 1. Physical layer (exists)

| Box | What | Address | Source |
|-----|------|---------|--------|
| OPNsense 26.1.9 | router, VLANs, DHCP, firewall, AdGuard DNS, HAProxy, WireGuard | LAN `192.168.1.1`, IOT `.20.1`, APP `.50.50`, WAN `192.168.100.2/30` | `docs/network.md` |
| NETGEAR GS308EP | switch; IOT VLAN 20 tagged to Proxmox ports, VLAN 51 tagged to router + `nic2` | `192.168.1.2` | `docs/network.md` |
| Proxmox VE 9.2.2 | Pentium J4205 (4 cores), 15 GiB RAM; system on Crucial MX500 250 GB (`local` 66 GiB, `local-lvm` 137 GiB thin) | `192.168.20.20`, `proxmox.dkhomelabserver.xyz` | live host |
| HP t620 | Home Assistant OS (to install) | `192.168.20.13`, `hass.dkhomelabserver.xyz` | DHCP map, AdGuard rewrite |

SMART 2026-10-19: SA500 PASSED, 37 h; Purple PASSED, 50 733 h (~5.8 years), no reallocated or pending sectors. Both still carry NTFS partitions (to be wiped, owner's decision).

Proxmox network: `vmbr0` VLAN-aware on `bond0` (active-backup `nic1` + `nic0`, MAC `3c:49:37:19:71:ae`), management `vmbr0.20`; `vmbr1` VLAN-aware on `nic2` for APP. Disks not yet given to anything: WD Red SA500 2 TB (`ata-WD_Red_SA500_2.5_2TB_2525GTD00073`), WD Purple 4 TB (`ata-WDC_WD40PURZ-85TTDY0_WD-WCC7K3KZKJKX`).

## 2. Virtual machines (Terraform)

Source: `terraform/environments/prod/terraform.tfvars`, `terraform/main.tf`. State: HCP Terraform org `dkhomelabserver`, workspace `homelab`. Image: Ubuntu 24.04 cloud image (noble), cloud-init, user `ubuntu-prod` (`main.tf`: `ubuntu-${environment}`), SSH key `UBUNTU_DOCKER_SSH_PUB`.

| VM | VMID | CPU / RAM | Disk | Network | IP / GW / DNS |
|----|------|-----------|------|---------|---------------|
| `ubuntu-nas` | 102 | 2 / 4 GiB | 32 GiB `local-lvm` + SA500 + Purple by-id | `vmbr0` tag 20 (IOT) | `192.168.20.12/24`, `.20.1`, `.20.1` |
| `ubuntu-apps` | 101 | 2 (`cpu_type=host`) / 8 GiB | 48 GiB `local-lvm` | `vmbr1` tag 51 (APP) | `192.168.50.30/26`, `.50.50`, `.50.50` |

Totals: 4 of 4 vCPU, 12 of 15 GiB RAM, 80 of 137 GiB thin pool. Proxmox itself keeps ~3 GiB.

## 3. NAS (`ubuntu-nas`, Ansible `deploy-storage.yml`)

Decided 2026-10-19 (owner): layout by data type, not by quotas - media total is ~300-400 GB.

| Disk | Holds | Why |
|------|-------|-----|
| SA500 2 TB SSD | all media: Immich, music, video, Syncthing sync | hot data, read often; 4-5x headroom |
| Purple 4 TB HDD | backups + Samba share `share` (installers) | cold, large, sequential |

- NFS: exports for `ubuntu-apps` only (`192.168.50.0/26`); `ubuntu-apps` mounts at `/mnt/homelab`; firewall APP -> `.20.12` TCP 2049/111 (exists). Paths in `compose/core/docker-compose.nfs.yml` stay.
- Samba on `ubuntu-nas`: share `share` on the Purple; the owner's admin account has access to everything, more users later; clients LAN `192.168.1.0/24` and WireGuard `10.10.10.0/24` only (`hosts allow` - IOT devices sit in the NAS subnet). Name `nas.dkhomelabserver.xyz` (AdGuard rewrite).
- `share` is not backed up (installers can be downloaded again). Media backup to pCloud is deferred until prod runs (media already exists on pCloud).
- Not implemented yet: formatting/mounting the passed disks inside the NAS VM (today `deploy-storage.yml` would create the exports on the 32 GiB root disk), Samba, the by-id values in `config/storage.yml`.

## 4. Applications (`ubuntu-apps`, Ansible `deploy-core.yml` + Docker Compose)

Source: `config/services.yml`, `compose/core/docker-compose.yml` (versions pinned, #23), `compose/grocery/`. All on `192.168.50.30`. Compose profiles `auth,media` on by default. Accounts: `config/identities.yml` (admin user `admin`, prod mail `prod-homelabnotifications@pm.me`), passwords from GH `prod` secrets / Bitwarden; `utils/bootstrap-apps.sh` configures them headlessly.

| Prio | App | Port | Notes |
|------|-----|------|-------|
| P0 | PostgreSQL 16 | 5432 | DBs homelab, linkwarden, firefly3, actual, trilium, grafana, easytodo, todo_grocery |
| P0 | Portainer | 9000 / 9443 | bootstrap; manages the Grocery stack |
| P0 | pgAdmin | 5050 | |
| P0 | Homarr | 7575 | board seeded from `services.yml`; password set once in UI |
| P0 | Trilium | 8082 | |
| P0 | Actual | 5006 | |
| P0 | Linkwarden | 3001 | |
| P0 | Authelia | 9091 | profile `auth` |
| P0 | Omni-tools / DumbWhois / BentoPDF | 8083 / 8084 / 8085 | |
| P0 | Grocery | 8101 | built on the guest from its repo at pinned `grocery_ref`; DB/role/schema by `deploy-core.yml`; **public** via HAProxy |
| P1 | Syncthing | 8384 (+22000, 21027) | peers by hand |
| P1 | Navidrome | 4533 | music on NFS |
| P1 | Jellyfin | 8096 | profile `media`; video on NFS |
| P1 | Immich (+ ML, Valkey, own Postgres) | 2283 | profile `media`; photos on NFS |
| P2 | Beszel hub | 8090 | agent needs a hub key (profile `beszel-agent`, off) |
| P2 | Dozzle | 8080 | container logs; Docker socket |
| P2 | Diun | - | new image tags to stdout |
| P2 | Zotify | 4381 | Spotify OAuth by hand |

Reachability: LAN, WireGuard and IOT can open APP; APP reaches the internet and the NAS NFS only (`docs/network.md`).

## 5. Public access

`grocery.dkhomelabserver.xyz` -> WAN `192.168.100.2:443` -> OPNsense HAProxy (Let's Encrypt via ACME) -> backend `grocery-app`. Everything else is LAN/VPN only.

## 6. Backups (`homelab-backup.timer` on `ubuntu-apps`, daily 03:15)

Source: `config/storage.yml`, `utils/backup/run-all.sh`, `deploy-storage.yml`. Destination `/mnt/homelab/backups` (NFS -> Purple). Retention: 2 newest per stream. Offsite: rclone -> `pcloud:homelab-backups` (DR copy, not the media libraries, which are already on pCloud).

| Stream | Script | Runs from |
|--------|--------|-----------|
| postgres (both Postgres) | `pg-dump.sh` | apps |
| volumes (named Docker volumes, not media) | `volumes.sh` | apps |
| repo-zip | `repo-zip.sh` | apps |
| opnsense `config.xml` | `opnsense.sh` | apps -> router SSH |
| homeassistant `.tar` | `ha-pull.sh` (`HA_TOKEN`) | apps -> `.20.13` |
| vzdump 101/102 | `vzdump.sh` | needs a Proxmox host |
| offsite | `rclone-offsite.sh` (`RCLONE_CONFIG`) | apps -> internet |

Restore: `utils/backup/restore-pg.sh --replace` (`knowledge/rebuild.md` step 7).

## 7. Monitoring

Beszel hub (host metrics; agent off until keyed), Dozzle (logs), Diun (image updates, stdout only), smoke/infra tests `utils/run-tests.sh --env prod`. F10 alerting (mail to `prod-homelabnotifications@pm.me`) is not built; Grafana has a database but no service.

## 8. How it is deployed

1. Terraform from the laptop the first time (`TF_WORKSPACE=homelab`, `TF_VAR_*` from GH `prod` / Bitwarden): the prod runner lives on `ubuntu-apps`, so it cannot run its own first apply (`docs/f3-proxmox.md`).
2. Disks: `utils/pve-attach-nas-disks.sh --env prod` after `by_id` is filled.
3. GitHub runner `homelab-prod` on `ubuntu-apps` (`setup-github-runner.sh`).
4. From then on, merge to `main`: `infra-plan` / `infra-apply-prod` (Terraform) and `apps-deploy-prod` (Ansible `deploy-core` + `deploy-storage`, then tests) on `[self-hosted, homelab-prod]`, environment `prod`; the PR plan `infra-plan` uses `prod-plan` (`docs/f3-proxmox.md` "PR plan").
5. Restore data (step 7 of `rebuild.md`), HAProxy check, `run-tests.sh --env prod`.

## 9. Gaps found while writing this (2026-10-19)

1. ~~HAProxy backend pointed at `192.168.50.30:8080` (Dozzle)~~ - fixed on the router: `8101` (`utils/f2-opnsense-haproxy.sh`, #35).
2. ~~SSH user mismatch `ubuntu` vs `ubuntu-prod`~~ - fixed: inventory and `services.yml` use `ubuntu-prod` (#35).
3. ~~Prod reused the DEV key and a June password~~ - fixed: own key `homelab_prod_ed25519`, new password hash, the prod deploy installs the key on the runner (#35).
4. ~~NAS disks: no by-id, nothing formats or mounts them~~ - fixed in #35: serials, one-time wipe opt-in, LABEL mounts, `crossmnt`, nfs-server guard, Samba; tested on DEV with two test disks. Still to run on prod after `terraform apply`: attach, then the opt-in format.
5. **Backups that cannot run from `ubuntu-apps`:** `vzdump.sh` needs a Proxmox host (timer on apps -> SKIP); `opnsense.sh` and `ha-pull.sh` need APP -> router SSH and APP -> `.20.13`, which the APP firewall blocks; `opnsense.sh` also needs a key on the router.
6. **Authelia is configured for `homelab.local`** (DEV) only; prod needs a domain under `dkhomelabserver.xyz` plus AdGuard rewrites for the app names.
7. **Monitoring alerts:** no notifier for Diun/Beszel; F10 not built.
8. ~~Workflow Terraform version prod `1.15.6` vs DEV `1.16.3`~~ - all workflows and the HCP workspace `homelab` on 1.16.3 since 2026-10-19, before the first prod state.
9. ~~APP -> NAS rules passed every TCP port~~ (port in a top-level `<destinationport>` that pf ignores) - fixed on the router: NFS 2049/111 plus SSH 22 from `.50.30` only (`utils/f2-opnsense-nas-ports.sh`, #35).
