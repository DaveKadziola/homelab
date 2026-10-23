# Dev — nested Proxmox (libvirt) + Terraform IaC

> **Status:** TF + GHA; the imperative `create-dev-vm.sh` it replaced was removed on 2026-10-20.

## Architecture

```text
Laptop (runner homelab-dev)
└── libvirt VM "Proxmox"  →  nested PVE :8006
    └── TF: ubuntu-apps-dev @ 192.168.122.50
```

Same `terraform/` module as prod; different `environments/dev/terraform.tfvars` and its own state in HCP Terraform workspace **`homelab-dev`** (execution mode local, set by `TF_WORKSPACE`).

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
| `infra-plan-dev.yml` | PR → `develop` | `terraform plan -refresh=false` (HCP workspace `homelab-dev`), environment `dev-plan` ("PR plan" below) |
| `infra-apply-dev.yml` | push `develop` / manual | `terraform apply` |
| `apps-deploy-dev.yml` | push `develop` | Ansible → deploy `compose/core` |

Apps stack details + test/prod checklist: [`docs/f4-apps-dev.md`](f4-apps-dev.md).

### PR plan (environment `dev-plan`)

`Infra Plan Dev` runs on pull requests to `develop`; `Infra Apply Dev` runs on the push after the
merge. Before 2026-10-20 both started on the same push and the plan often ran after the apply. The
environment `dev` allows only `develop` and `main` and rejects pull request refs, so the plan uses `dev-plan`:
no reviewers, every branch, a read-only token (`PVEAuditor`), `-refresh=false` and a dummy SSH
password - the same design as `prod-plan` ([`f3-proxmox.md`](f3-proxmox.md) "PR plan"). DEV uses the
token `root@pam!terraform`; the plan token is `root@pam!plan`.

One-time setup from the laptop (no value is printed):

```bash
D=root@192.168.122.219; K=~/.ssh/homelab_dev_ed25519; R=DaveKadziola/homelab
ssh -i $K $D 'pveum user token add root@pam plan --privsep 1 --output-format json' \
  | jq -r .value | ./utils/bw-store.py --env dev-plan --stdin PROXMOX_API_TOKEN_SECRET
ssh -i $K $D 'pveum acl modify / --tokens "root@pam!plan" --roles PVEAuditor'
gh api -X PUT repos/$R/environments/dev-plan
gh variable set PROXMOX_API_TOKEN_ID --env dev-plan --repo $R --body 'root@pam!plan'
for v in PROXMOX_API_URL PROXMOX_SSH_USERNAME UBUNTU_DOCKER_SSH_PUB; do
  gh variable set "$v" --env dev-plan --repo $R --body "$(gh api repos/$R/environments/dev/variables/$v --jq .value)"
done
gh secret set PROXMOX_API_TOKEN_SECRET --env dev-plan --repo $R < ~/.homelab-secrets/dev-plan/PROXMOX_API_TOKEN_SECRET
jq -r '.credentials["app.terraform.io"].token' ~/.terraform.d/credentials.tfrc.json | gh secret set TF_API_TOKEN --env dev-plan --repo $R
plain="$(cat ~/.homelab-ubuntu-apps-dev-pass)"   # same hash rule as utils/sync-secrets-to-github.py
printf '%s\n' "$plain" | openssl passwd -6 -salt "$(printf '%s' "$plain" | sha256sum | cut -c1-16)" -stdin \
  | gh secret set UBUNTU_DOCKER_PASSWORD --env dev-plan --repo $R
unset plain
```

## Local apply

```bash
./utils/ensure-dev-proxmox.sh
./utils/dev-apply-local.sh   # TF_WORKSPACE=homelab-dev, plan then apply; needs `terraform login` once
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
| Branch | `develop` | `main` |
| VLAN | flat `.122.x` | IOT 20 + APP 51 |

Prod networking bugs still need prod plan; dev catches **TF/provider/cloud-init** regressions early.
