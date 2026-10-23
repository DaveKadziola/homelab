# utils

Scripts run from the laptop unless a line says otherwise. A `*-remote.sh` file is the half that runs on the router: the script without `-remote` pipes it over SSH. Do not run a `-remote` script on the laptop.

`prepare-infra.py` checks secret names first, fills the ones `gen-app-credentials.sh` can create, and stops if the Proxmox API token is still missing. It does not start a GitHub workflow.

## Where to start

| Script | Does |
| --- | --- |
| `prepare-infra.py --env dev` | Start nested Proxmox, record its API URL, write the DEV host network, start the HAOS twin |
| `prepare-infra.py --env prod` | Check only: the prod host answers and the network file matches. Changes nothing |
| `run-tests.sh --env dev\|prod --suite all` | Test suites in `tests/` |
| `dev-apply-local.sh` | Terraform apply for the nested DEV Proxmox. Races Infra Apply Dev if that run is already going |

## DEV host

| Script | Does |
| --- | --- |
| `ensure-dev-proxmox.sh` | Start the libvirt VM named `Proxmox` if it is stopped |
| `bootstrap-dev-proxmox.sh` | Write the nested Proxmox API URL into the GitHub `dev` environment. `--set-token` also stores the API token |
| `dev-haos-vm.sh` | Create or start the HAOS twin. `--dry-run`, `--undo` |

## Proxmox host

| Script | Does |
| --- | --- |
| `bootstrap-proxmox.sh` | Prod host: snippets datastore, no-subscription repo, hide the subscription notice, set `PROXMOX_API_URL`. `--dry-run`, `--upgrade`, `--set-token` |
| `proxmox-preflight.sh` | Prod API answers, and VM ids 101 and 102 are free |
| `proxmox-verify.sh` | Prod host and the GitHub prod API URL. Also runs `opnsense-verify.sh` |
| `pve-network.py --env dev\|prod` | Write `config/pve/interfaces.<env>` to the host, with auto-revert. `--dry-run` prints the diff |
| `pve-attach-nas-disks.sh` | Pass SA500 and Purple through to `ubuntu-nas` on the physical host |
| `pve-backup-job.py --env dev\|prod` | Nightly vzdump of the VMs onto the NAS |
| `pve-ci-runner-lxc.sh` | The prod runner container on the physical host |

## Router

Each row is the laptop script. It stops or reverts itself unless a check passes.

| Script | Does |
| --- | --- |
| `opnsense-verify.sh` | Ping and name checks from the laptop. Does not log in |
| `opnsense-dns.sh` | DNS on every VLAN goes to AdGuard, including UDP |
| `adguard-rewrites.sh` | Names such as `jellyfin.dkhomelabserver.xyz` resolve at home |
| `opnsense-dhcp.sh` | IOT DHCP reservations for Proxmox and Home Assistant |
| `opnsense-app-vlan.sh` | APP is a plain VLAN 51, not QinQ |
| `opnsense-dmz.sh` | Move DMZ out of the APP subnet |
| `opnsense-app-egress.sh` | APP may go to the internet |
| `opnsense-nas-ports.sh` | APP may open only NFS (and SSH from the apps VM) on the NAS |
| `opnsense-iot.sh` | Remove the IOT allow-all rule |
| `opnsense-wan-http.sh` | Close TCP 80 on the WAN |
| `opnsense-haproxy.sh` | Public Grocery backend is port 8101 |
| `opnsense-haproxy-acme.sh` | Certificate for `grocery.dkhomelabserver.xyz` and enable HAProxy |
| `opnsense-grocery-xff.sh` | Grocery backend sends X-Forwarded-For |
| `opnsense-apply.sh` | Older bundle: NFS rules from APP to the NAS, plus a backup |
| `opnsense-backup-key.sh` | NAS key that can only read the router config |
| `backup-opnsense-config.sh` | Download `config.xml` once |
| `collect-homelab-macs.sh` | Print MAC addresses for `docs/network.md` |

## Secrets

| Script | Does |
| --- | --- |
| `gen-app-credentials.sh` | Create names from `config/identities.yml` in GitHub, the laptop cache, and Bitwarden. Skips a name that already exists. `--secret <NAME> --paste` stores a value you paste, e.g. a token another service issued |
| `bootstrap-secrets.sh` | Older generator for the first infra secrets. Prefer `gen-app-credentials.sh` |
| `bw-store.py` | Copy one cache file into Bitwarden, or queue the name while the vault is locked |
| `sync-cache-to-bitwarden.sh` | Wrapper: the logic is `bw-store.py` |
| `sync-secrets-to-github.py` | Copy local files into a GitHub environment. Prints nothing |
| `rotate-secrets.py` | New values in Bitwarden, GitHub, and the cache |
| `export-secrets-for-bitwarden.sh` | Write a text file to paste into Bitwarden. Delete the file after |

## Apps, backups, monitoring

| Script | Does |
| --- | --- |
| `bootstrap-apps.sh` | Run `bootstrap/<app>.sh` in order. Deploy calls this on the apps host |
| `bootstrap/` | One app each: Authelia, Beszel, Homarr, Immich, Jellyfin, Linkwarden, Navidrome, pgAdmin, Portainer, Syncthing. `lib.sh` is shared. `homarr_board.py` and `beszel_config.py` are the pieces those shell files call |
| `gen-homarr-board.sh` | Build the Homarr tile list from `config/services.yml` |
| `gen-proxy-config.py` | Build the Caddyfile and the Authelia rules from `config/services.yml` |
| `ha.py` | Home Assistant: status, deploy `homeassistant/packages`, backup |
| `kuma-sync.py` | Make Uptime Kuma match `config/monitoring.yml` for monitors named `homelab:` |
| `host-updates.sh` | Apt packages due, and a newer Ubuntu cloud image |
| `trivy-scan.py` | Trivy scan of the running images; `--mail` mails only when the HIGH and CRITICAL findings with a fix change |
| `nic-errors.sh` | Receive errors on the Proxmox NICs. `--check` fails only when a counter grew |
| `alert-mail.sh` | Send stdin through the SMTP settings in the environment |
| `backup/` | `run-all.sh` on the apps host (Postgres, volumes, repo zip, offsite). `run-nas.sh` on the NAS (Home Assistant, its UI YAML, OPNsense). `check-fresh.py` ages. `restore-pg.sh` and `restore-scratch.sh` restore. `check-prune.sh` checks retention |
| `setup-github-runner.sh` | Register the laptop or prod runner |
| `setup-rclone-pcloud.sh` | Finish the pCloud remote after its OAuth login |
| `tf-plan-risk.py` | Say whether a prod Terraform plan must stop for approval |
| `release-notes.py` | Next `vX.Y.Z` and bullet-point release notes for what Apps Deploy Prod deployed |
