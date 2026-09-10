# Architecture

Homelab v2 is a greenfield rebuild: **Terraform** creates VMs on Proxmox, **Ansible** configures the guest, **Docker Compose** runs the apps, **GitHub Actions** deploys. Two environments share the same module; they do not share state, secrets, or networks.

```
Laptop (dev)
  libvirt VM "Proxmox"  →  nested PVE :8006 (node name `dev`)
    ubuntu-apps-dev @ 192.168.122.50
      compose/core + compose/grocery
      self-hosted runner `homelab-dev`

Prod (physical — after sign-off)
  OPNsense  →  Proxmox host 192.168.20.20 (node `proxmox`)
    ubuntu-nas   192.168.20.12   IOT VLAN 20   NFS exporter (not OMV/TrueNAS — see storage.md)
    ubuntu-apps  192.168.50.30   APP VLAN 51   Docker + runner `homelab-prod`
    HA T620      192.168.20.13   IOT VLAN 20   Home Assistant
  WireGuard 10.10.10.0/24
```

## Source of truth

| What | Where |
|------|--------|
| Service ports, health, compose profiles | [`config/services.yml`](../../config/services.yml) |
| Accounts and secret *names* | [`config/identities.yml`](../../config/identities.yml) |
| Secret *values* | Bitwarden → GitHub Environment → `~/.homelab-secrets/<env>/` |
| VM sizing / IPs | `terraform/environments/<env>/terraform.tfvars` |
| NFS / backup streams | [`config/storage.yml`](../../config/storage.yml) |
| Network map | [`docs/network.md`](../network.md) · this KB [`networking.md`](networking.md) |

A port exists in `services.yml` first, then in compose. Never only in a markdown table.

## What is in scope vs not

- **In scope on DEV today:** P0–P2 apps on `ubuntu-apps-dev`, Authelia, Immich (local volumes), F7 bootstrap + F7-C tests, F5 loopback NFS + backup timer + restore suite.
- **Not built yet:** SA500/Purple passthrough, rclone OAuth, HAOS on the T620, public HAProxy/ACME on grocery, F9 merge-to-`main` wipe, F10 monitoring.

## Related

- [`infrastructure.md`](infrastructure.md) — Proxmox, TF, runners
- [`deployment.md`](deployment.md) — how code reaches a host
- [`rebuild.md`](rebuild.md) — clean-room order
