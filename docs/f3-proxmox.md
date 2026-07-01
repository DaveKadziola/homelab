# F3 — Proxmox Terraform + prod runner

> **Status:** prep (2026-07-01).  
> **Blocks:** F2 gate (F2-01…03 + backup), Proxmox online at `192.168.20.20`.  
> **Related:** [network.md](network.md), [opnsense-baseline.md](opnsense-baseline.md)

## Goal

Create on Proxmox:

| VM | IP | Role |
|----|-----|------|
| `ubuntu-nas-prod` | `192.168.20.12` | NFS (no Docker) |
| `ubuntu-apps-prod` | `192.168.50.30` | Docker + **homelab-prod** runner |

Host mgmt stays **`192.168.20.20`** (existing DHCP on OPNsense).

---

## F3 checklist

| ID | Task | Tool |
|----|------|------|
| F3-01 | Proxmox reachable (SSH/API) | `./utils/f3-verify.sh` |
| F3-02 | API token `terraform-prov@pam!terraform` | Proxmox UI → Datacenter → Permissions |
| F3-03 | GH prod variables → real `PROXMOX_API_URL` | `./utils/bootstrap-f3-proxmox.sh` |
| F3-04 | `terraform plan` (TFC local exec) | `infra-plan.yml` or laptop |
| F3-05 | `terraform apply` on `main` | `infra-apply-prod.yml` (needs prod runner — chicken/egg) |
| F3-06 | DHCP static for VM MACs on OPNsense | after first boot |
| F3-07 | Install `homelab-prod` runner on `ubuntu-apps` | `setup-github-runner.sh` |
| F3-08 | Update `docs/network.md` MAC column | F2-07 |

---

## Bootstrap order (first prod apply)

Prod runner lives **on** `ubuntu-apps`, so the **first** apply is usually from **laptop**:

```bash
cd terraform
export TF_VAR_environment=prod
# load TF_VAR_* from gh / Bitwarden
terraform init
terraform plan -var-file=environments/prod/terraform.tfvars
terraform apply -var-file=environments/prod/terraform.tfvars
```

After VMs exist:

```bash
./utils/setup-github-runner.sh --label homelab-prod --url https://github.com/DaveKadziola/homelab
```

Then merge `homelab-v2` → `main` for CI-driven applies.

---

## Proxmox API token (F3-02)

1. `https://192.168.20.20:8006` → Datacenter → Permissions → API Tokens  
2. User: `terraform-prov@pam` (or `root@pam` for bootstrap only)  
3. Token ID: `terraform` → full ID `terraform-prov@pam!terraform`  
4. Uncheck **Privilege Separation** if using broad TF role  
5. Role: `Administrator` or custom TF role  
6. Store secret in Bitwarden → `gh secret set PROXMOX_API_TOKEN_SECRET --env prod`

---

## OPNsense after F3

Add DHCP static mappings (Services → DHCPv4):

| Host | IP | VLAN |
|------|-----|------|
| `ubuntu-nas` | `.20.12` | IOT (vlan03) |
| `ubuntu-apps` | `.50.30` | APP (opt6) |

Get MAC: Proxmox → VM → Hardware → Network, or `ip link` in guest.

---

## F3 gate → F4

- [ ] Both VMs running with planned IPs  
- [ ] `homelab-prod` runner online  
- [ ] NFS rule tested: from apps → `showmount -e 192.168.20.12` (after NAS export in F4)  
- [ ] `infra-plan.yml` green on PR to `main`

**Next:** F4 — P0 Compose on `ubuntu-apps`.
