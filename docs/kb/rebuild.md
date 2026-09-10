# Rebuild / migration runbook

Scenario: *clean Proxmox, new hardware, different storage, or a nested DEV rebuild*.

Do this in order. A later step will fail if an earlier one is skipped.

## Dependency graph

```
OPNsense config.xml
    → Proxmox install + API token
        → terraform apply (NAS + apps)
            → Ansible base (users, Docker)
                → compose/core + grocery
                    → F7 bootstrap (accounts)
                        → restore data (F5 — not implemented)
                            → HAProxy / ACME (prod grocery)
                                → utils/run-tests.sh --env <env>
```

## 1. OPNsense — **manual** · **blocker**

Without the router, VLANs, DHCP statics, WireGuard, and HAProxy do not exist.

- Restore `config.xml` (or replay [`docs/opnsense-baseline.md`](../opnsense-baseline.md)).
- Secrets: OPNsense admin (Bitwarden), WG keys.
- Verify: gateways `.20.1` / `.50.50`, WG `10.10.10.1`, occupied IPs unchanged.
- Time: 30–90 min.
- **DEV variant:** skip. libvirt `default` is enough.

## 2. Proxmox on metal — **semi-auto**

- Install PVE. Node name in prod tfvars is `proxmox`.
- `utils/bootstrap-f3-proxmox.sh` + API token `terraform-prov@pam!terraform`.
- Secrets: `PROXMOX_API_TOKEN_SECRET`, `PROXMOX_SSH_PASSWORD`, `PROXMOX_API_URL`.
- Verify: `utils/f3-verify.sh` / `utils/f3-proxmox-preflight.sh`.
- Time: 1–2 h.
- **DEV variant:** `utils/ensure-dev-proxmox.sh` + `utils/bootstrap-dev-proxmox.sh --set-token`. Node name **`dev`**.

## 3. Terraform VMs — **auto**

- Prod: TFC workspace `homelab`, apply on `main` (approval).
- Dev: `utils/dev-apply-local.sh` + local state.
- Secrets: `UBUNTU_DOCKER_PASSWORD`, SSH key pair.
- Data from backup: none yet. A1 SA500/Purple passthrough is still a gap.
- Verify: guests ping; **plan must not say `must be replaced`**.
- Time: 15–30 min.
- **Abort** if the plan destroys `ubuntu-apps`.

## 4. Ansible base — **auto**

- `ansible/playbooks/deploy-core.yml` (Docker, compose sync, `.env`).
- Secrets: everything in `config/identities.yml` + `service_secrets` via `~/.homelab-secrets/<env>/` or GH env.
- Verify: `docker ps`, `.env` is `0640` `ubuntu-*:docker`.
- Time: 10–20 min.

## 5. Compose + grocery — **auto / Portainer**

- Core: Ansible `docker compose up`.
- Grocery: Portainer stack from `compose/grocery/` (see [`apps/grocery.md`](apps/grocery.md)).
- Time: 10 min + image pulls.

## 6. F7 bootstrap — **auto** (some SKIP)

```bash
sudo env HOMELAB_SECRETS_DIR=/opt/homelab/secrets \
  HOMELAB_CONFIG_DIR=/opt/homelab/config \
  HOMELAB_COMPOSE_DIR=/opt/homelab/compose \
  /opt/homelab/utils/bootstrap-apps.sh --env <env> --host 127.0.0.1
```

- Manual leftovers: Zotify OAuth ([`apps/zotify.md`](apps/zotify.md)), Homarr password if CLI hangs, Syncthing **peers** (device IDs).
- Verify: table in [`operations.md`](operations.md).
- Time: 5–15 min.

## 7. Restore data — **manual / missing**

Blocked on F5. When jobs exist: `pg_dump` per DB → volumes → Immich/media from NFS/pCloud → HA `.tar`.

Until then a rebuild gives **empty apps with known passwords**, not the old library.

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
| New storage | TF A1 + Ansible NFS (not written). Re-point Immich/Jellyfin mounts. |
| Renumber network | **Do not**, unless you also move printer/Tuya/NPM. Edit `docs/network.md` first. |
| Nested DEV on a new laptop | Steps 2-DEV → 3-DEV → 4 → 5 → 6 → 9. No OPNsense, no restore. |

## Related

- [`architecture.md`](architecture.md) · [`dr.md`](dr.md) · [`lessons-learned.md`](lessons-learned.md)
