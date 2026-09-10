# Infrastructure

## Dev (laptop)

| Piece | Detail |
|-------|--------|
| Hypervisor | libvirt VM named `Proxmox` |
| Nested PVE UI | `https://192.168.122.219:8006` (IP can move; `utils/ensure-dev-proxmox.sh`) |
| Node name | **`dev`**, not `pve` — `proxmox_node_name` in tfvars |
| Apps guest | `ubuntu-apps-dev` VMID 101 · `192.168.122.50` |
| Sizing | 6144 MiB RAM · 2 cores · `cpu_type=host` · 27G `local-lvm` |
| SSH | `ubuntu-dev@192.168.122.50` · `~/.ssh/homelab_dev_ed25519` |
| TF state | **local** `terraform/environments/dev/terraform.tfstate` (gitignored) |
| Helper | `utils/dev-apply-local.sh` — moves `cloud.tf` aside (HCP block breaks local apply) |

`cpu_type=host` is required: Immich ML / NumPy needs x86-64-v2. `kvm64`/`qemu64` dies with `Illegal instruction`.

Cloud-init is first-boot only. The VM resource `lifecycle { ignore_changes = [initialization] }` so a rehashed snippet does not destroy Immich volumes. `dev-apply-local.sh` uses a **deterministic SHA256 salt** for `openssl passwd -6`.

## Prod (planned / as-built network)

| Piece | Detail |
|-------|--------|
| Proxmox host | `192.168.20.20` · node `proxmox` · NIC1 mgmt |
| NAS | `ubuntu-nas` · `192.168.20.12` · 4 GiB · SA500 + Purple (A1 mount **not implemented**) |
| Apps | `ubuntu-apps` · `192.168.50.30` · 8192 MiB · 48G · `cpu_type=host` |
| TF | HCP TFC workspace `homelab` via `terraform/cloud.tf` |
| Do not apply | until physical PVE is online and you sign off DEV |

## Runners

| Label | Host | Workflows |
|-------|------|-----------|
| `homelab-dev` | laptop / nested path | `ci-validate`, `infra-*-dev`, `apps-deploy-dev`, `tests-dev` |
| `homelab-prod` | `ubuntu-apps` (F3) | `infra-*` / `apps-deploy-prod` on `main` |

Start the DEV runner: `sudo ./svc.sh start` in `~/actions-runner-homelab`. Without sudo it goes quietly offline and CI never fires.

## Related

- [`docs/dev-proxmox.md`](../dev-proxmox.md)
- [`docs/f3-proxmox.md`](../f3-proxmox.md)
- [`lessons-learned.md`](lessons-learned.md)
