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

Paste the secret into `./utils/bootstrap-f3-proxmox.sh --set-token` (hidden input): it sets `PROXMOX_API_TOKEN_SECRET` in GH `prod`, writes `~/.homelab-secrets/prod/PROXMOX_API_TOKEN_SECRET` (mode 600) and stores Bitwarden `homelab/PROXMOX_API_TOKEN_SECRET/prod` (queued while the vault is locked). Never print it.

---

## PR plan (environment `prod-plan`)

`Infra Plan Prod` (`.github/workflows/infra-plan.yml`) runs `terraform plan` for workspace `homelab`
on every PR to `main`: no apply, no state lock. It cannot use the environment `prod`, which allows
only the branch `main`: GitHub rejected the job on PR #38 with `Branch "refs/pull/38/merge" is not
allowed to deploy to prod`. It uses `prod-plan` instead: no reviewers, every branch allowed, and only
what a plan reads. Because every branch can use it, its Proxmox token is read-only (`PVEAuditor`);
`TF_API_TOKEN` is the only value in it that can write (HCP state). The SSH password is a dummy in the
workflow: plan does not connect over SSH. `Infra Apply Prod` and `Apps Deploy Prod` stay in `prod`
with the approval.

The plan runs with `-refresh=false`. With refresh the read-only token failed on PR #42:
`Permission check failed (/vms/101, VM.Config.Disk)` for the VM disks, and both cloud-init snippets
showed as "will be created". Without refresh it compares the configuration with the state (local
check 2026-10-20: "No changes"), so it shows what the PR changes; drift on the host shows only in the
plan of `Infra Apply Prod`, which uses the full token.

One-time setup from the laptop (no value is printed):

```bash
# 1. Read-only token on the existing user: privilege separation on, PVEAuditor on /.
install -d -m 700 ~/.homelab-secrets/prod-plan
ssh root@192.168.20.20 'pveum user token add homelab-prod@pam plan --privsep 1 --output-format json' \
  | jq -r .value > ~/.homelab-secrets/prod-plan/PROXMOX_API_TOKEN_SECRET
chmod 600 ~/.homelab-secrets/prod-plan/PROXMOX_API_TOKEN_SECRET
utils/bw-store.py --env prod-plan PROXMOX_API_TOKEN_SECRET   # Bitwarden, or queued while locked
ssh root@192.168.20.20 'pveum acl modify / --tokens "homelab-prod@pam!plan" --roles PVEAuditor'

# 2. Environment without reviewers and without a branch policy.
gh api -X PUT repos/DaveKadziola/homelab/environments/prod-plan

# 3. Variables: the plan token ID, the rest copied from prod.
gh variable set PROXMOX_API_TOKEN_ID --env prod-plan --body 'homelab-prod@pam!plan'
for v in PROXMOX_API_URL PROXMOX_SSH_USERNAME UBUNTU_DOCKER_SSH_PUB; do
  gh variable set "$v" --env prod-plan \
    --body "$(gh api "repos/DaveKadziola/homelab/environments/prod/variables/$v" --jq .value)"
done

# 4. Secrets. TF_API_TOKEN: the laptop's `terraform login` token (or Bitwarden homelab/TF_API_TOKEN/prod).
gh secret set PROXMOX_API_TOKEN_SECRET --env prod-plan < ~/.homelab-secrets/prod-plan/PROXMOX_API_TOKEN_SECRET
jq -r '.credentials["app.terraform.io"].token' ~/.terraform.d/credentials.tfrc.json \
  | gh secret set TF_API_TOKEN --env prod-plan
plain="$(cat ~/.homelab-secrets/prod/UBUNTU_DOCKER_PASSWORD)"
printf '%s\n' "$plain" \
  | openssl passwd -6 -salt "$(printf '%s' "$plain" | sha256sum | cut -c1-16)" -stdin \
  | gh secret set UBUNTU_DOCKER_PASSWORD --env prod-plan
unset plain
```

`UBUNTU_DOCKER_PASSWORD` must be the same hash as in `prod`: the cloud-init snippet embeds it
(`terraform/main.tf:52`). Step 4 hashes it with the fixed salt of `utils/sync-secrets-to-github.py`.
If the PR plan shows `proxmox_virtual_environment_file.cloud_config` replaced while nothing changed,
`prod` was hashed with another salt: set the same value in `prod` too (repeat the last command with
`--env prod`). The VMs ignore cloud-init changes (`terraform/main.tf:149-151`), so the next apply
only rewrites the snippet.

Check: the next PR to `main` shows `Infra Plan Prod` green with the plan in its log.

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
