# OPNsense — disaster recovery

> **Related:** [../docs/opnsense-baseline.md](../docs/opnsense-baseline.md), `utils/backup-opnsense-config.sh`

## Backup

| Method | Frequency | Location |
|--------|-----------|----------|
| `config.xml` export | After every change; F5 automated | `opnsense/backups/` (local, gitignored) |
| Offsite | F5 | Purple NAS / pCloud `homelab-backups/opnsense/` |

## Restore (full router)

1. Reinstall OPNsense (same version major if possible) or reset to factory
2. Assign interfaces (WAN, LAN, VLAN parents) — match labels from backup notes
3. **System → Configuration → Backups → Restore** — upload saved `config.xml`
4. Reboot
5. Verify: VLANs, DHCP, WireGuard handshake, HAProxy, firewall rules
6. Re-issue ACME cert if hostname/WAN changed

## Restore (partial)

Not recommended — OPNsense is monolithic `config.xml`. Prefer full restore.

## What is not in config.xml

- Let's Encrypt account keys (usually included in backup)
- Hardware-specific interface mapping may differ after NIC reorder — fix in UI after restore

## Test plan (yearly)

1. Download current `config.xml`
2. Boot OPNsense VM or spare hardware (optional)
3. Restore backup and confirm WG + one internal ping

---

*Keep at least **2** newest config backups per A15 retention.*
