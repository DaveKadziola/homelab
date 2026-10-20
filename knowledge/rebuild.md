Status: draft
Last reviewed: 2026-10-20
Scope: rebuild order from OPNsense to tests, for prod metal and nested DEV

# Rebuild / migration runbook

Scenario: *clean Proxmox, new hardware, different storage, or a nested DEV rebuild*.

Do this in order. A later step will fail if an earlier one is skipped.

**Before step 4:** `./utils/gen-app-credentials.sh --env <env> --all` (or restore `~/.homelab-secrets/<env>/` from Bitwarden). GH cannot read secrets back.

**DEV Authelia:** add `192.168.122.50 authelia.homelab.local homelab.local` on the **client**. Nested PVE itself is not created by this repo — `ensure-dev-proxmox.sh` only starts an existing libvirt domain named `Proxmox`.

**Grocery:** image `easy-todo-grocery-nodb:latest` is built from `DaveKadziola/easytodo-grocery-list` (pinned `grocery_ref` in `deploy-core.yml`), not this repo. DB `todo_grocery`, its role and schema are created by `deploy-core.yml`, not by `postgres-init` (step 5).

## Dependency graph

```
OPNsense config.xml
    → Proxmox install + API token
        → terraform apply (NAS + apps)
            → Ansible base (users, Docker)
                → compose/core + grocery
                    → F7 bootstrap (accounts)
                        → restore data (F5 dumps / volume tars)
                            → HAProxy / ACME (prod grocery)
                                → utils/run-tests.sh --env <env>
```

## 1. OPNsense — **manual** · **blocker**

Without the router, VLANs, DHCP statics, WireGuard, and HAProxy do not exist.

- Restore `config.xml` (or replay [`docs/opnsense-baseline.md`](../docs/opnsense-baseline.md)).
- Secrets: OPNsense admin (Bitwarden), WG keys.
- Verify: gateways `.20.1` / `.50.50`, WG `10.10.10.1`, occupied IPs unchanged.
- Time: 30–90 min.
- **DEV variant:** skip. libvirt `default` is enough.

## 2. Proxmox on metal — **semi-auto**

- Install PVE and put it on its network as in [`docs/f3-proxmox.md`](../docs/f3-proxmox.md#bare-metal-install): installer values, VLAN 20 by hand on the console, then `config/pve/interfaces.prod` copied to the host and one reboot (unverified: bare-metal path not run end to end). Reinstalling the running host erases VMs 101/102 on `local-lvm`; read that section first. Node name in prod tfvars is `proxmox`.
- Later host network changes: `utils/pve-network.py --env prod` (diff, backup, auto-revert) (unverified: apply and revert path not run on any host yet; DEV control runs pending, only `--dry-run` was run).
- API tokens `homelab-prod@pam!terraform` (`prod`) and `homelab-prod@pam!plan` (`prod-plan`, read-only), then `utils/bootstrap-f3-proxmox.sh --upgrade` (post-install: `pve-no-subscription`, no subscription notice, HA off).
- Secrets: `PROXMOX_API_TOKEN_SECRET` (`prod`, `prod-plan`), `PROXMOX_SSH_PASSWORD` (the new root password). The command that creates each one also writes the laptop cache and Bitwarden (`utils/bw-store.py --stdin`, as in `docs/f3-proxmox.md`), then `gh secret set` reads the cache file; `utils/bw-store.py --pending` stores what waited for a locked vault. Variable: `PROXMOX_API_URL`.
- Verify: `utils/pve-network.py --env prod --dry-run` prints `no change`; `utils/f3-verify.sh` / `utils/f3-proxmox-preflight.sh`.
- Time: 1–2 h.
- **DEV variant:** `utils/ensure-dev-proxmox.sh` + `utils/bootstrap-dev-proxmox.sh --set-token`. Node name **`dev`**. Host network: `config/pve/interfaces.dev`, written by `PVE_KEY=~/.ssh/homelab_dev_ed25519 ./utils/pve-network.py --env dev`; DEV is where the apply and revert path is tried before any prod apply.

## 3. Terraform VMs — **auto**

- Prod: TFC workspace `homelab`, apply on `main` (approval only for a risky plan, [0004](decisions/0004-ci-autonomy-and-prod-risk-gate.md)).
- Dev: `utils/dev-apply-local.sh`, state in HCP workspace `homelab-dev`.
- Secrets: `UBUNTU_DOCKER_PASSWORD`, SSH key pair.
- Data from backup: none on first apply. Prod: after the apply and a clean `terraform plan`, attach SA500/Purple with `utils/pve-attach-nas-disks.sh --env prod --dry-run`, then without `--dry-run` (slot, serial and by-id from `config/storage.yml` `passthrough[]`); `terraform plan` again must show no changes. New disks: update `passthrough[]` first, do not invent by-id. Do not apply a NAS VM on nested DEV.
- Verify: guests ping; **plan must not say `must be replaced`**.
- Time: 15–30 min.
- **Abort** if the plan destroys `ubuntu-apps`.
- A merge to `homelab-v2` starts `Infra Apply Dev` and, for `ansible/**` / `compose/**`, `Apps Deploy Dev` by itself; check the Actions tab before applying by hand, or the two runs race (drill 2026-10-19).
- A recreated guest has a new SSH host key: `ssh-keygen -R <guest-ip>` on the laptop and the runner, or tests fail on the old `known_hosts` entry.

## 4. Ansible base — **auto**

- `ansible/playbooks/deploy-storage.yml` first, as the deploy workflows do: NFS must be up before compose binds the media libraries. Prod NAS: finds SA500/Purple by serial, formats only a blank disk, mounts them by LABEL; then NFS, Samba (`share`, `media`) and `homelab-backup.timer`. DEV = loopback NFS and Samba on the same guest.
- **A DR rebuild never passes `nas_wipe`.** A disk that carries its LABEL is mounted as it is; `nas_wipe` erases a disk and is only for the first format ([`storage.md`](storage.md#attach-and-format-run-order)).
- Then `ansible/playbooks/deploy-core.yml` (Docker, compose sync, `.env`).
- Secrets: everything in `config/identities.yml` + `service_secrets` via `~/.homelab-secrets/<env>/` or GH env.
- Verify: `docker ps`, `.env` is `0640` `ubuntu-*:docker`.
- Time: 10–20 min.
- The first run on a fresh guest can fail while pulling images (`network is unreachable` on an IPv6 address, drill 2026-10-19); rerun `Apps Deploy Dev`. Do **not** run `docker compose up` by hand before step 6: Portainer only accepts its first admin for a few minutes after it starts.

## 5. Compose + grocery — **auto / Portainer**

- Core: Ansible `docker compose up`.
- Grocery: automated since 2026-10-19 (`deploy-core.yml` + `portainer.sh`):
  - the image `easy-todo-grocery-nodb:latest` is built on the guest from the app repo at the pinned `grocery_ref` when it is missing (it is never pushed to a registry);
  - role `prod_todo_grocery` (password `GROCERY_DB_PASSWORD`) and database `todo_grocery` are created when missing;
  - schema `prod` comes from the app repo's `ddl/3_3-ddl_prod.sql` at the same ref when the schema is missing (role `postgres` in that file is mapped to `homelab`);
  - the Portainer bootstrap redeploys the stack without pulling when it exists but its container is not running.
  - Verify: `curl http://<guest>:8101/` -> 200. Restoring a `todo_grocery` dump on top of the created schema needs the database emptied first (step 7).
- Time: 10 min + image pulls.

## 6. F7 bootstrap — **auto** (some SKIP)

```bash
sudo env HOMELAB_SECRETS_DIR=/opt/homelab/secrets \
  HOMELAB_CONFIG_DIR=/opt/homelab/config \
  HOMELAB_COMPOSE_DIR=/opt/homelab/compose \
  /opt/homelab/utils/bootstrap-apps.sh --env <env> --host 127.0.0.1
```

- Manual leftovers: Homarr password if CLI hangs, Syncthing **peers** (device IDs).
- Verify: table in [`operations.md`](operations.md).
- Time: 5–15 min.

## 7. Restore data — **semi-auto** (F5)

On the apps guest, after NFS is mounted. A rebuilt DEV guest has an empty `/mnt/homelab/backups`: put the copy back first, from the laptop:

```bash
ssh -i ~/.ssh/homelab_dev_ed25519 ubuntu-dev@<guest> 'sudo tar -C /mnt/homelab -xzf -' < backups.tar.gz
```

The dumps are plain SQL without `--clean`, so they load only into an **empty** database; the fresh deploy has already created and filled most of them, so use `--replace` (drop `WITH (FORCE)` + create). Stop the app first, or it reconnects to a half-restored database:

```bash
cd /opt/homelab
B=/mnt/homelab/backups/postgres
R="sudo env HOMELAB_SECRETS_DIR=/opt/homelab/secrets ./utils/backup/restore-pg.sh --env <env>"

docker stop homelab-core-linkwarden-1
$R --db linkwarden --file $B/linkwarden-….sql.gz --replace --owner linkwarden
docker start homelab-core-linkwarden-1

docker stop homelab-core-immich-server-1 homelab-core-immich-machine-learning-1
$R --db immich --file $B/immich-….sql.gz --replace \
   --container homelab-core-immich-postgres-1 --user postgres --password-secret IMMICH_DB_PASSWORD
docker start homelab-core-immich-machine-learning-1 homelab-core-immich-server-1

$R --db todo_grocery --file $B/todo_grocery-….sql.gz --replace   # grocery stack stopped in Portainer
# volume tars: stop the app, untar into the named volume, start
```

`--owner` matters for linkwarden: the app connects as `linkwarden` and must own its tables; without it they would belong to `homelab`, the user the script connects as. Immich has its own Postgres container and superuser.

DEV proof: `./utils/run-tests.sh --env dev --suite restore` (throwaway DB). On 2026-10-19 the commands above restored linkwarden (18 tables, owner `linkwarden`, app 200) and immich (row counts equal to the dump, `isInitialized` true) over the databases of a fresh deploy. Copy `/mnt/homelab/backups` off a DEV guest before wiping it: the DEV NFS export lives on the same guest (`ssh … 'sudo tar -C /mnt/homelab -czf - backups' > backups.tar.gz`). Run `restore-pg.sh` from a file or a terminal, not inside a script piped to `ssh … bash -s`: its `docker exec -i` reads the rest of that script as input.

On a **prod** rebuild the artefacts come from the NAS backup directory (or pCloud): Postgres dumps, volume tars, the HA full backup (`HA_BACKUP_PASSWORD`), VM dumps; the SA500 libraries are not in the backups. A rebuild without those artefacts still gives empty media libraries with known passwords.

The Samba share on Purple (`/srv/purple/share`) is in no backup and no offsite copy: if Purple is lost, the share is not recoverable. The media on SA500 has no homelab copy yet either (pCloud media backup deferred, [decision 0002](decisions/0002-nas-layout-and-samba.md)).

## 8. DNS / ACME / HAProxy — **manual** (prod)

- Backend `192.168.50.30:8101` for `grocery.dkhomelabserver.xyz`.
- Secrets: ACME / existing certs in GH (`SSL_*`, planned).

## 9. Tests — **auto**

```bash
./utils/run-tests.sh --env prod --suite all   # or --env dev
```

“Looks OK in the browser” is not the gate.

## Variants

| Variant | What changes |
|---------|----------------|
| New hypervisor | Step 2 + 3. Keep OPNsense if the LAN is unchanged. |
| New storage | Update `passthrough[]` (by-id, serial, slot, label), `pve-attach-nas-disks.sh --env prod --dry-run` then the real run, `deploy-storage.yml` (a blank disk is formatted; `nas_wipe` only for a new disk that still holds foreign data), prod compose NFS override. |
| Renumber network | **Do not**, unless you also move printer/Tuya. Edit `docs/network.md` first. |
| Nested DEV on a new laptop | Steps 2-DEV → 3-DEV → 4 → 5 → 6 → 9. No OPNsense, no restore. |

## Related

- [`architecture.md`](architecture.md) · [`dr.md`](dr.md) · [`lessons-learned.md`](lessons-learned.md) · drills: [`2026-09-10`](rebuild-drill-2026-09-10.md), [`2026-10-19`](rebuild-drill-2026-10-19.md)
