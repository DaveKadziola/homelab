# Dev — nested Proxmox (libvirt) + Terraform IaC

> **Status:** replaces `create-dev-vm.sh` (imperative) with TF + GHA.

## Architecture

```text
Laptop (runner homelab-dev)
└── libvirt VM "Proxmox"  →  nested PVE :8006
    └── TF: ubuntu-apps-dev @ 192.168.122.50
```

Same `terraform/` module as prod; different `environments/dev/terraform.tfvars` and **local state** (`environments/dev/terraform.tfstate`, gitignored).

## One-time setup

1. **Nested Proxmox** installed in libvirt VM `Proxmox` (already on laptop).
2. Start + detect IP:
   ```bash
   ./utils/ensure-dev-proxmox.sh
   ```
3. **API token** on nested PVE UI → Datacenter → Permissions → API Tokens.
4. **GitHub dev env:**
   ```bash
   ./utils/bootstrap-dev-proxmox.sh --set-token
   ```
5. Node name is **`dev`** (hostname in UI title). Override only if you renamed it.

## CI/CD

| Workflow | Trigger | Action |
|----------|---------|--------|
| `infra-plan-dev.yml` | PR/push `homelab-v2` | `terraform plan` (local state) |
| `infra-apply-dev.yml` | push `homelab-v2` / manual | `terraform apply` |
| `apps-deploy-dev.yml` | push `homelab-v2` | Ansible → `ubuntu-apps-dev` |

## Local apply

```bash
./utils/ensure-dev-proxmox.sh
cd terraform
terraform init -backend=false -reconfigure
export TF_VAR_environment=dev
# export TF_VAR_proxmox_* from Bitwarden / gh
terraform apply -state=environments/dev/terraform.tfstate -var-file=environments/dev/terraform.tfvars
```

## Migrate from old homelab-dev (libvirt Ubuntu)

If `homelab-dev` VM still exists and conflicts:

```bash
virsh -c qemu:///system destroy homelab-dev
virsh -c qemu:///system undefine homelab-dev --remove-all-storage
```

Then run `infra-apply-dev` or local apply above.

## vs prod

| | Dev | Prod |
|---|-----|------|
| Hypervisor | nested PVE (libvirt) | physical PVE `.20.20` |
| State | local file | TFC `homelab` |
| Branch | `homelab-v2` | `main` |
| VLAN | flat `.122.x` | IOT 20 + APP 51 |

Prod networking bugs still need prod plan; dev catches **TF/provider/cloud-init** regressions early.
