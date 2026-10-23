# Infrastructure

## Dev (laptop)

| Piece | Detail |
|-------|--------|
| Hypervisor | libvirt VM named `Proxmox` |
| Nested PVE UI | `https://192.168.122.219:8006` (IP can move; `utils/ensure-dev-proxmox.sh`) |
| Node name | **`dev`**, not `pve` — `proxmox_node_name` in tfvars |
| Apps guest | `ubuntu-apps-dev` VMID 101 · `192.168.122.50` |
| Sizing | 6144 MiB RAM · 2 cores · `cpu_type=host` · 33G `local-lvm` |
| SSH | `ubuntu-dev@192.168.122.50` · `~/.ssh/homelab_dev_ed25519` |
| TF state | HCP Terraform workspace **`homelab-dev`** (execution mode local; `TF_WORKSPACE`) |
| Helper | `utils/dev-apply-local.sh` — plan + apply with `TF_WORKSPACE=homelab-dev` |

`cpu_type=host` is required: Immich ML / NumPy needs x86-64-v2. `kvm64`/`qemu64` dies with `Illegal instruction`.

Cloud-init is first-boot only. The VM resource `lifecycle { ignore_changes = [initialization] }` so a rehashed snippet does not destroy Immich volumes. `dev-apply-local.sh` uses a **deterministic SHA256 salt** for `openssl passwd -6`.

## Prod (as-built, running since 2026-10-20)

| Piece | Detail |
|-------|--------|
| Proxmox host | `192.168.20.20` · node `proxmox` · `proxmox.dkhomelabserver.xyz` · PVE 9.2.2 · mgmt `vmbr0.20` on `bond0` (nic0 + nic1 backup since 2026-10-21) |
| NAS | `ubuntu-nas` · `192.168.20.12` · 2 GiB (4 GiB until the release after 2026-10-23) · NFS + Samba · SA500 2 TB SSD (`scsi1`) = all media, Purple 4 TB HDD (`scsi2`) = backups + Samba share (`config/storage.yml`; attached by `pve-attach-nas-disks.sh`, `qm config 102` 2026-10-20) |
| Apps | `ubuntu-apps` · `192.168.50.30` · 9216 MiB (8192 until the release after 2026-10-23) · 48G · `cpu_type=host` |
| TF | HCP TFC workspace `homelab` via `terraform/cloud.tf` + `TF_WORKSPACE=homelab` |
| Apply | only through the release flow: a push to `main` runs Infra Apply Prod; a risky plan waits for the owner in `prod-gate` ([0004](decisions/0004-ci-autonomy-and-prod-risk-gate.md)) |

## Runners

| Label | Host | Workflows |
|-------|------|-----------|
| `homelab-dev` | laptop / nested path | `ci-validate`, `infra-*-dev`, `apps-deploy-dev`, `tests-dev` |
| `homelab-prod` | LXC `ci-runner` (CT 110, `192.168.20.14`, IOT VLAN 20) on the prod Proxmox host | `infra-*` / `apps-deploy-prod` on `main` |

Start the DEV runner: `sudo ./svc.sh start` in `~/actions-runner-homelab`. Without sudo it goes quietly offline and CI never fires.

The prod runner container is built and converged by `utils/pve-ci-runner-lxc.sh` (`--dry-run` first), outside the prod Terraform state: an apply that replaced its own runner would end the job half way. Unprivileged Debian 13, no SSH server (`pct enter 110` on the host), nftables drops all inbound traffic, the runner runs as user `runner` without sudo.

Terraform is installed on both runners, not downloaded per job: the laptop has the apt package `terraform`, `ci-runner` gets the release zip (SHA256-checked) into `/usr/local/bin` from `utils/pve-ci-runner-lxc.sh`, which also keeps `/usr/local/bin` in the runner's job `PATH` (`.path`) and `LANG=C.UTF-8` in its `.env`: `config.sh` copies both from the shell that registered it. Each workflow's `Check Terraform` step fails when the runner's version is not the one it expects (1.16.3). To upgrade, change `TF_VERSION` in the script, the version in every `Check Terraform` step and the laptop package together. The HCP token reaches Terraform as `TF_TOKEN_app_terraform_io` in the Terraform steps only.

## Related

- [`docs/dev-proxmox.md`](../docs/dev-proxmox.md)
- [`docs/f3-proxmox.md`](../docs/f3-proxmox.md)
- [`lessons-learned.md`](lessons-learned.md)
