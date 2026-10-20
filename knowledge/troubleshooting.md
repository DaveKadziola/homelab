# Troubleshooting

Symptoms first. Root-cause write-ups go in [`lessons-learned.md`](lessons-learned.md) in the same change that fixes them.

## Nested Proxmox / VM

| Symptom | Check |
|---------|--------|
| TF wants to replace `ubuntu-apps` | Stop. Cloud-init drift or state lag. Confirm `lifecycle.ignore_changes = [initialization]`. Do not apply a replace. |
| `cloud {}` / TFC error on laptop (`No workspace selected`, 401) | Set `TF_WORKSPACE=homelab-dev` (DEV) or `homelab` (prod); run `terraform login` once. `utils/dev-apply-local.sh` sets it. |
| Wrong node | Nested PVE node is `dev`, not `pve`. |
| Immich ML crash-loop / `Illegal instruction` | Guest `cpu_type` must be `host`. |
| Disk full / image pull fails | DEV guest is 27G; `docker system df`. |
| Nested Proxmox and `ubuntu-apps-dev` stop answering, one vCPU at 100 %, journal just stops | LVM-thin pool `pve/data` full: `lvs pve/data` on the nested PVE. With `when full = queue` every write waits forever. Set `lvchange --errorwhenfull y pve/data`, free space, then `virsh destroy` + `utils/ensure-dev-proxmox.sh`. Test: `infra/storage/thin-pool`. |

## Compose / host

| Symptom | Check |
|---------|--------|
| `docker compose` permission denied on `.env` | File must be `ubuntu-dev:docker` `0640`, not `root:root` `0600`. |
| Deploy from GitHub Actions breaks auth (`password authentication failed`, `postgres-init` exit 2) but a local deploy works | GitHub secret holds a wrong value. Secrets once set with `gh secret set … --body -` are the literal `-`. Re-sync: `utils/sync-secrets-to-github.py --env <env> --apply`. |
| `docker compose` command missing | `docker-compose-v2` package (Ansible installs it). |
| pgAdmin `:5050` hung | mem_limit must be ≥ 512m (384m OOM-kills gunicorn). |
| Immich postgres restart | mem_limit ≥ 768m. |
| BentoPDF connection reset | Map `8085:8080`, not `:80`. |
| Grocery ports invisible in Portainer | Do not use `network_mode: host`. Use `compose/grocery` bridge. |
| Portainer “timed out for security purposes” | Create/reset admin immediately after first start (`utils/bootstrap/portainer.sh`). Helper line is `login: \`password\``. |
| Portainer login fails after bootstrap | Helper reset ate the old password. Re-run portainer bootstrap; use `~/.homelab-secrets/dev/PORTAINER_ADMIN_PASSWORD`, not `~/.homelab-portainer-dev-pass`. |

## Auth

| Symptom | Check |
|---------|--------|
| Authelia “check your credentials” / no session on IP | Use `https://authelia.homelab.local:9091` + `/etc/hosts`. |
| pgAdmin will not start / rejects email | Mailbox cannot be `*.local`. |
| Immich reset hangs | `immich-admin reset-admin-password` needs a TTY — bootstrap uses pexpect. |
| Navidrome CLI “inappropriate ioctl” | `docker exec -t` + pexpect (`utils/bootstrap/navidrome.sh`). Do not pipe. |
| Syncthing basic auth 401 | Current Syncthing uses `POST /rest/noauth/auth/password` (session), not HTTP basic. |
| Homarr CLI hangs | Do not wait on `homarr-cli`. Do not put the password on host argv. Set once in the UI if API login fails. |
| Jellyfin wizard already done | No official reset. DEV: wipe `jellyfin_config` or update the `Users` row. First wizard on this lab created `root`; it is now `admin`. |

## Storage / backups

| Symptom | Check |
|---------|--------|
| `/mnt/homelab` not NFS | `deploy-storage.yml` with `HOMELAB_ENV` set; `exportfs -v`; `showmount -e 127.0.0.1` |
| Timer silent | `systemctl status homelab-backup.timer`; `journalctl -u homelab-backup` |
| `run-all.sh` cannot read secrets | It must run as root (`HOMELAB_SECRETS_DIR=/opt/homelab/secrets`) |
| rclone / HA / vzdump “failed” | They must SKIP with a reason on DEV, not fail the timer |
| Immich photos vanished after compose | You applied `docker-compose.nfs.yml` on DEV. Do not. |

## CI

| Symptom | Check |
|---------|--------|
| Workflows queued forever | Runner `homelab-dev` offline → `sudo ./svc.sh start`. |
| Config tests fail on `BESZEL_KEY` | It is `issued_by: beszel` — not required in GH until hub bootstrap. |
| Setup Terraform hangs: the downloaded zip in `_work/_temp` stops 2-3 KB short of the full file, the socket to HashiCorp's CDN sits in `FIN-WAIT-1` (seen 2026-10-20 on the laptop and on `ci-runner`) | The step times out after 5 minutes; re-run the job. Root cause unknown: curl downloads of the same file from both hosts never stalled. |

## Network

| Symptom | Check |
|---------|--------|
| Host on IOT gets a DHCP lease, but the gateway stays `INCOMPLETE` in `ip neigh` and ping says `Destination Host Unreachable` | The switch port delivers VLAN 20 tagged. Use a VLAN 20 interface on the host, or make the port untagged VLAN 20 / PVID 20 (T620, 2026-10-20). |
