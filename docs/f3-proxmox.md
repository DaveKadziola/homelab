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
| F3-02 | API token `homelab-prod@pam!terraform` (done 2026-10-19) | `pveum` on the host, see below |
| F3-03 | GH prod variables → real `PROXMOX_API_URL` | `./utils/bootstrap-f3-proxmox.sh` |
| F3-04 | `terraform plan` | `./utils/f3-proxmox-preflight.sh` then plan |
| F3-05 | `terraform apply` on `main` | `infra-apply-prod.yml` (needs prod runner — chicken/egg) |
| F3-06 | DHCP static for VM MACs on OPNsense | after first boot |
| F3-07 | Install `homelab-prod` runner on `ubuntu-apps` | `setup-github-runner.sh` |
| F3-08 | Update `docs/network.md` MAC column | F2-07 |

---

## Before first apply — clean conflicting VMs

```bash
./utils/f3-proxmox-preflight.sh   # lists VMs; remove vmid 101/102 if occupied
```

Legacy VMs on Proxmox with the same **vmid** or names must be **stopped and destroyed** in the UI before `terraform apply`.

## Bootstrap order (first prod apply)

Prod is built from `main` only (owner, 2026-10-19): `Infra Apply Prod` on a push to `main`, then
`Apps Deploy Prod` after it (`workflow_run`), both in the GitHub environment `prod` that needs the
owner's approval. The prod runner lives on `ubuntu-apps`, which does not exist before the first
apply, so the first run uses a temporary runner on the laptop:

1. `./utils/bootstrap-f3-proxmox.sh` (API URL, `snippets` on datastore `local`).
2. Temporary runner: `RUNNER_INSTALL_DIR=~/actions-runner-homelab-prod ./utils/setup-github-runner.sh --label homelab-prod --name homelab-prod-laptop-bootstrap`, started with `./run.sh`.
3. Tag the old `main` as `legacy-pre-v2`, open the PR `homelab-v2` -> `main` (`Infra Plan Prod` runs the plan), merge, approve `Infra Apply Prod`.
4. Attach and format the NAS disks by hand (`knowledge/storage.md`), never in CI.
5. Approve `Apps Deploy Prod` (or re-run it with workflow_dispatch after step 4).
6. Permanent runner on `ubuntu-apps` (`setup-github-runner.sh --label homelab-prod`), then remove the laptop runner (`./config.sh remove`).

---

## Proxmox API token (F3-02)

Full ID `homelab-prod@pam!terraform` (matches the GH `prod` variable `PROXMOX_API_TOKEN_ID`), role `Administrator` on `/`, privilege separation off:

```bash
pveum user add homelab-prod@pam --comment "Terraform homelab-v2 (prod)"
pveum acl modify / --users homelab-prod@pam --roles Administrator
pveum user token add homelab-prod@pam terraform --privsep 0 --output-format json   # "value" = secret, shown once
```

The secret goes to `~/.homelab-secrets/prod/PROXMOX_API_TOKEN_SECRET` (mode 600), Bitwarden `homelab/PROXMOX_API_TOKEN_SECRET/prod` and `gh secret set PROXMOX_API_TOKEN_SECRET --env prod < file`. Never print it.

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
