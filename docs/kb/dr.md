# Disaster recovery

DR here means “the building burned / the disk died / I bought new hardware”, not “restart a container”.

## What you can recover today

| Asset | How |
|-------|-----|
| Repo + IaC | git (`homelab-v2` / `main`) |
| Secret *names* | [`docs/secrets-inventory.md`](../secrets-inventory.md) · `config/identities.yml` |
| Secret *values* | Bitwarden (mandatory). GH cannot give them back. |
| Nested DEV VMs | `utils/ensure-dev-proxmox.sh` + `utils/dev-apply-local.sh` + Ansible |
| Authelia hash | committed `users_database.yml` + `utils/bootstrap/authelia.sh` |

## What you cannot recover today

- Immich photos, Jellyfin/Navidrome libraries, Trilium/Actual/Linkwarden data — **no F5 backups**
- NAS contents — disks not even mounted in TF
- OPNsense live config — unless you exported `config.xml` yourself

## Order after a total loss

Follow [`rebuild.md`](rebuild.md). Short version: OPNsense → PVE + token → Terraform VMs → Ansible → compose → F7 bootstrap → restore data (when F5 exists) → HAProxy → `utils/run-tests.sh`.

A nested-PVE drill on the laptop is the F9 gate before merging `homelab-v2` → `main`. That drill is not this document.
