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

Host mgmt stays **`192.168.20.20/24`** on `vmbr0.20`, static on the host from `config/pve/interfaces.prod` (Bare-metal install below; later changes with `./utils/pve-network.py --env prod`). OPNsense keeps a DHCP static map for its MAC (`docs/network.md`).

---

## F3 checklist

| ID | Task | Tool |
|----|------|------|
| F3-01 | Proxmox reachable (SSH/API) | `./utils/f3-verify.sh` |
| F3-02 | API token `homelab-prod@pam!terraform` (done 2026-10-19) | `pveum` on the host, see below |
| F3-03 | Host post-install (pve-no-subscription, no subscription notice, HA off on one node), GH prod variable `PROXMOX_API_URL` | `./utils/bootstrap-f3-proxmox.sh --dry-run`, then `--upgrade` |
| F3-04 | `terraform plan` | `./utils/f3-proxmox-preflight.sh` then plan |
| F3-05 | `terraform apply` on `main` | `infra-apply-prod.yml` (needs prod runner — chicken/egg) |
| F3-06 | DHCP static for VM MACs on OPNsense | after first boot |
| F3-07 | Install `homelab-prod` runner on `ubuntu-apps` | `setup-github-runner.sh` |
| F3-08 | Update `docs/network.md` MAC column | F2-07 |

---

## Bare-metal install

For a fresh PVE on this hardware. Not run end to end yet. Values are those of the host as built on
2026-10-19: `config/pve/interfaces.prod`, plus its `/etc/hosts` and `/etc/resolv.conf` read on 2026-10-20.

**Reinstalling the running host** erases `local-lvm` on the MX500, and with it the root disks of
VM 101 `ubuntu-apps` and VM 102 `ubuntu-nas` (`knowledge/prod-target.md`). There is no vzdump of
the prod VMs (`knowledge/dr.md`). First make sure the latest F5 dumps and volume tars are either on
Purple (`/srv/purple/backups`, `knowledge/backup.md`) or on the laptop (the `tar` command in
`knowledge/rebuild.md` step 7).

1. Installer:
   - Target disk: the Crucial MX500 250 GB, file system `ext4` (the current host, read 2026-10-20).
     Never the WD Red SA500 2 TB or the WD Purple 4 TB: they hold the NAS data (`config/storage.yml`).
   - Management interface: MAC `3c:49:37:19:71:ae` (`nic1`, Intel). The current host pins the names
     `nic0`-`nic2` in `/usr/local/lib/systemd/network/50-pmx-nic{0,1,2}.link` (read 2026-10-20);
     written by the installer or later: `<how they were pinned on 2026-10-19>`.
   - Hostname (FQDN) `proxmox.dkhomelabserver.xyz`, IP `192.168.20.20/24`, gateway `192.168.20.1`,
     DNS `192.168.20.1`. `proxmox` is the node name in the prod tfvars.
   - Root password: a new value. Store it on the laptop before typing it in the installer; this
     writes `~/.homelab-secrets/prod/PROXMOX_SSH_PASSWORD` (mode 600) and Bitwarden, and step 5
     sends it to GitHub:
     `read -rsp 'root password: ' PW && printf '%s' "$PW" | ./utils/bw-store.py --env prod --stdin PROXMOX_SSH_PASSWORD; unset PW`.
   - Country, time zone, keyboard, e-mail: `<installer locale and e-mail>`.
2. Console, after the first boot. The switch ports deliver VLAN 20 tagged, so the installer's
   untagged `vmbr0` gets no ARP replies (`docs/network.md`). Check the NIC names, then put the
   address on VLAN 20 until step 4 (it is gone after a reboot):

   ```bash
   ip -br link   # nic0 70:85:c2:53:e0:ac, nic1 3c:49:37:19:71:ae, nic2 3c:49:37:19:71:af - otherwise stop
   ip addr del 192.168.20.20/24 dev vmbr0
   ip link add link vmbr0 name vmbr0.20 type vlan id 20
   ip addr add 192.168.20.20/24 dev vmbr0.20
   ip link set vmbr0.20 up
   ip route replace default via 192.168.20.1 dev vmbr0.20
   ping -c2 192.168.20.1
   ```

   A temporarily untagged switch port (GS308EP, `192.168.1.2`) would also work, but no file records
   the port numbers or their settings, and the port must be tagged again before the reboot in
   step 4. The commands above change nothing outside the host.
3. Laptop: forget the old host key and install the root key (asks for the root password once):

   ```bash
   KEY=~/.ssh/homelab_prod_pve_ed25519   # root key of the prod host
   ssh-keygen -R 192.168.20.20
   ssh-copy-id -i "$KEY" root@192.168.20.20
   ```

4. Host network from the repo, by file and reboot. This avoids switching the installer's `vmbr0`
   to `bond0` live, which has not been tried:

   ```bash
   ssh -i "$KEY" root@192.168.20.20 'cp -p /etc/network/interfaces /etc/network/interfaces.installer'
   scp -i "$KEY" config/pve/interfaces.prod root@192.168.20.20:/etc/network/interfaces
   ssh -i "$KEY" root@192.168.20.20 reboot
   # after the reboot - must print "no change":
   PVE_KEY="$KEY" ./utils/pve-network.py --env prod --dry-run
   ```

   If the host does not answer after the reboot, run this on the console:
   `cp /etc/network/interfaces.installer /etc/network/interfaces && reboot`. Then repeat step 2 and
   find the cause on the console before trying again. Later network changes go through
   `./utils/pve-network.py --env prod` (diff, backup, auto-revert).
5. Secrets for the new host (no value is printed). The command that creates a secret also stores it
   in the laptop cache and Bitwarden (`utils/bw-store.py --stdin`). With the vault locked the name
   waits in `~/.homelab-secrets/.bw-pending`; after `export BW_SESSION="$(bw unlock --raw)"`,
   `./utils/bw-store.py --pending` stores it.
   - Root password (step 1), used by Terraform's SSH login (`terraform/providers.tf`):
     `gh secret set PROXMOX_SSH_PASSWORD --env prod < ~/.homelab-secrets/prod/PROXMOX_SSH_PASSWORD`.
   - API tokens: "Proxmox API token (F3-02)" below, then "PR plan" step 1 and its
     `gh secret set PROXMOX_API_TOKEN_SECRET --env prod-plan` line.
6. `PVE_KEY="$KEY" ./utils/bootstrap-f3-proxmox.sh --upgrade` (first with `--dry-run`) switches apt to
   `pve-no-subscription`, hides the subscription notice, turns HA off on the single node, upgrades the
   packages (reboot if it prints `REBOOT NEEDED`) and enables `snippets` on `local`; the API URL does
   not change. Then start the temporary laptop runner (Bootstrap order step 2) and re-run
   `Infra Apply Prod` with workflow_dispatch. Continue with `knowledge/rebuild.md` step 3 (attach the
   NAS disks with `utils/pve-attach-nas-disks.sh`, never `nas_wipe`) through step 9. Bootstrap order
   steps 3-4 are for the first install only: the NAS disks already hold data.

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

1. `./utils/bootstrap-f3-proxmox.sh --upgrade` (post-install, API URL, `snippets` on datastore `local`).
2. Temporary runner: `RUNNER_INSTALL_DIR=~/actions-runner-homelab-prod ./utils/setup-github-runner.sh --label homelab-prod --name homelab-prod-laptop-bootstrap`, started with `./run.sh`.
3. Tag the old `main` as `legacy-pre-v2`, open the PR `homelab-v2` -> `main` (`Infra Plan Prod` runs the plan), merge, approve `Infra Apply Prod`.
4. Attach and format the NAS disks as in [`knowledge/storage.md`](../knowledge/storage.md#attach-and-format-run-order), never in CI.
5. Approve `Apps Deploy Prod` (or re-run it with workflow_dispatch after step 4).
6. Permanent runner on `ubuntu-apps` (`setup-github-runner.sh --label homelab-prod`), then remove the laptop runner (`./config.sh remove`).

---

## Proxmox API token (F3-02)

Full ID `homelab-prod@pam!terraform` (matches the GH `prod` variable `PROXMOX_API_TOKEN_ID`), role `Administrator` on `/`, privilege separation off:

```bash
ssh root@192.168.20.20 'pveum user add homelab-prod@pam --comment "Terraform homelab-v2 (prod)"'
ssh root@192.168.20.20 'pveum acl modify / --users homelab-prod@pam --roles Administrator'
ssh root@192.168.20.20 'pveum user token add homelab-prod@pam terraform --privsep 0 --output-format json' \
  | jq -r .value | ./utils/bw-store.py --env prod --stdin PROXMOX_API_TOKEN_SECRET \
  && gh secret set PROXMOX_API_TOKEN_SECRET --env prod < ~/.homelab-secrets/prod/PROXMOX_API_TOKEN_SECRET
```

The secret is shown once and never printed. `bw-store.py` writes it to
`~/.homelab-secrets/prod/PROXMOX_API_TOKEN_SECRET` (mode 600) and to Bitwarden
`homelab/PROXMOX_API_TOKEN_SECRET/prod` (queued while the vault is locked); then `gh secret set`
reads that file. If the token already exists, `pveum` fails, `bw-store.py` refuses the empty value
and changes nothing, and `gh secret set` does not run.

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
# Cache file (mode 600) and Bitwarden homelab/PROXMOX_API_TOKEN_SECRET/prod-plan in one step.
ssh root@192.168.20.20 'pveum user token add homelab-prod@pam plan --privsep 1 --output-format json' \
  | jq -r .value | ./utils/bw-store.py --env prod-plan --stdin PROXMOX_API_TOKEN_SECRET
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
