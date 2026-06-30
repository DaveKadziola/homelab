# OPNsense artifacts

Configuration lives on the **physical router** — not in this repo.

| Path | Purpose |
|------|---------|
| [docs/opnsense-baseline.md](../docs/opnsense-baseline.md) | F2 setup checklist |
| [docs/opnsense-ui-walkthrough.md](../docs/opnsense-ui-walkthrough.md) | OPNsense UI steps |
| [docs/wireguard.md](../docs/wireguard.md) | VPN clients |
| [docs/network.md](../docs/network.md) | IP/VLAN map |
| [RESTORE.md](RESTORE.md) | DR procedure |
| `backups/` | Local `config.xml` exports (gitignored) |

Backup:

```bash
./utils/backup-opnsense-config.sh
```
