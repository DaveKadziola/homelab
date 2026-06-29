# Network map — homelab v2

> **Status:** A4/A5 closed (2026-06-11). MAC addresses are placeholders until F3.  
> **Related:** [opnsense-baseline.md](opnsense-baseline.md) (F2 config), greenfield plan.

## VLAN overview

| VLAN / name | Gateway | DHCP range | Tag | Notes |
|-------------|---------|------------|-----|-------|
| LAN | 192.168.1.1 | .100–.200 | — | Default LAN |
| HOMEOFFICE | 192.168.10.1 | .100–.200 | — | |
| **IOT** | 192.168.20.1 | .100–.200 | **20** | Proxmox NIC1, HA T620, NAS VM |
| GUEST | 192.168.30.1 | .100–.200 | — | Guest WiFi |
| DMZ | 192.168.50.1 | .7–.14 | 50 | **Unused on start** (A5) |
| **APP** | 192.168.50.1 | .30–.62 | **51** | Docker / `ubuntu-apps` |
| **WireGuard VPN** | 10.0.0.1 | .7–.14 | — | Remote access |
| **dev libvirt** | 192.168.122.1 | DHCP | — | Laptop only; isolated from prod |

**Decision:** DMZ off; single APP segment on `192.168.50.0/24` with gateway **192.168.50.1** (OPNsense VLAN 51).

## Static IP reservations (OPNsense DHCP)

Configure in **F2** — replace MAC placeholders with real hardware addresses before **F3**.

| Host | VLAN | Tag | IP | MAC (placeholder) |
|------|------|-----|-----|-----------------|
| OPNsense IOT | IOT | 20 | 192.168.20.1 | (router interface) |
| OPNsense APP | APP | 51 | 192.168.50.1 | (router interface) |
| Proxmox host (NIC1) | IOT | 20 | **192.168.20.10** | `aa:bb:cc:dd:ee:01` |
| HP T620 (Home Assistant) | IOT | 20 | **192.168.20.11** | `aa:bb:cc:dd:ee:02` |
| `ubuntu-nas` | IOT | 20 | **192.168.20.12** | `aa:bb:cc:dd:ee:03` |
| `ubuntu-apps` | APP | 51 | **192.168.50.30** | `aa:bb:cc:dd:ee:04` |
| `homelab-dev` (laptop libvirt) | dev | — | DHCP (e.g. 192.168.122.229) | — |

## Proxmox NIC layout

| NIC | Role | VLAN / IP |
|-----|------|-----------|
| NIC1 | IOT / mgmt + trunk VM IOT | tag 20 |
| NIC2 | Pass-through SA500 + Purple → NAS VM | no IP |
| NIC3 | APP trunk → `ubuntu-apps` | tag 51 |

## Cross-VLAN traffic (F2 firewall)

| Source | Destination | Ports | Purpose |
|--------|-------------|-------|---------|
| APP (`192.168.50.0/24`) | IOT `192.168.20.12` | TCP 2049, 111 | NFS from `ubuntu-apps` to `ubuntu-nas` |
| WireGuard (`10.0.0.0/24`) | LAN / IOT / APP | per service | VPN access to internal services |
| Internet | OPNsense WAN | 443 | **Only** `grocery.dkhomelabserver.xyz` → HAProxy |

## DNS (A6)

| Name | Type | Target | Access |
|------|------|--------|--------|
| `grocery.dkhomelabserver.xyz` | A/AAAA | WAN IP | Public HTTPS (HAProxy) |
| Internal services | hosts / split-DNS | `.lan` or static | VPN-only |

Zone: **`dkhomelabserver.xyz`**

## Dev vs prod

| | Dev (laptop) | Prod (Proxmox) |
|---|--------------|----------------|
| Network | `192.168.122.0/24` | IOT 20 + APP 51 |
| VM | `homelab-dev` libvirt | `ubuntu-apps`, `ubuntu-nas` |
| Deploy branch | `homelab-v2` | `main` (after merge) |

---

*Update MAC column after hardware inventory (F3 gate).*
