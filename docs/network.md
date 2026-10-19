# Network map — homelab v2

> **Status:** A5 as-built aligned with OPNsense (2026-06-30).  
> **Related:** [opnsense-baseline.md](opnsense-baseline.md), greenfield plan.

## Dev pool (laptop only — no OPNsense)

| Role | Network | IP |
|------|---------|-----|
| libvirt `default` | `192.168.122.0/24` | GW `192.168.122.1` |
| **Dev** | `192.168.122.0/24` (nested PVE) | DHCP/static `.122.50` |
| `ubuntu-apps-dev` (TF) | same | **`192.168.122.50`** |
| GH branch | `homelab-v2` | env **dev** |

Dev is **isolated** from prod VLANs.

---

## Prod pool — OPNsense as-built (do not renumber existing devices)

### VLAN / gateways (router unchanged)

| VLAN | Tag | OPNsense interface | Gateway | Notes |
|------|-----|-------------------|---------|-------|
| IOT | 20 | vlan03 | `192.168.20.1/24` | Proxmox mgmt, NAS, HA T620 |
| APP | 51 | qinq01 (QinQ on vlan06) | **`192.168.50.50/26`** | Docker; DHCP **off** (range `.30`–`.62` configured but disabled; VMs use static IPs from cloud-init) |
| WireGuard | — | wg0 | **`10.10.10.1/24`** | port `51820`; not `10.0.0.0` |
| VPN (legacy VLAN) | 40 | vlan05 | `10.0.0.1/28` | separate from WG |

### Already occupied on IOT (do not change)

| IP | Device |
|----|--------|
| `192.168.20.10` | Canon printer |
| `192.168.20.11` | E1 Zoom |
| `192.168.20.20` | **Proxmox host** (NIC1 mgmt) |
| `192.168.20.50`–`.58` | Tuya / IoT |

### Homelab v2 slots (new DHCP static mappings at F3/F5)

| Role | VLAN | Tag | IP | MAC |
|------|------|-----|-----|-----|
| Proxmox host | IOT | 20 | **`192.168.20.20`** | `7c:d3:0a:1a:f5:10` (on router) |
| `ubuntu-nas` | IOT | 20 | **`192.168.20.12`** | VM NIC — set at F3 |
| HP T620 HAOS | IOT | 20 | **`192.168.20.13`** | T620 NIC — set at F5 |
| `ubuntu-apps` | APP | 51 | **`192.168.50.30`** | VM NIC — set at F3 |

**DMZ** (VLAN 50, `vlan06`, parent of the APP QinQ): `192.168.50.65/28` (`.64`–`.79`) since 2026-10-19, moved out of APP `192.168.50.0/26` (`utils/f2-opnsense-dmz.sh`). Unused; DHCP off. The dead legacy NPM `.50.2` (no ARP) lost its static map and its LAN/DMZ rules and its WAN port-forward (disabled).

---

## Proxmox — 3× NIC (one host IP, traffic separation)

| NIC | Layer-3 on host | Role |
|-----|-----------------|------|
| **NIC1** | **`192.168.20.20`** (IOT) | Proxmox API/SSH; trunk VLAN 20 → `ubuntu-nas` `.20.12` |
| **NIC2** | none | PCI passthrough SA500 + Purple → NAS VM disks only |
| **NIC3** | none on host | Trunk VLAN 51 → `ubuntu-apps` `.50.30` |

Host has **one** management IP. NIC2/NIC3 offload storage and app traffic from NIC1 — not multiple host IPs.

**F3 Terraform:** `vmbr0` vlan-aware on NIC1; APP VM on tag 51 (NIC3 trunk per cabling).

---

## Cross-VLAN firewall (F2)

| Source | Destination | Ports | Purpose |
|--------|-------------|-------|---------|
| APP net `192.168.50.0/26` (`opt6`) | `192.168.20.12` | TCP 2049, 111 | NFS apps → NAS |
| IOT (`opt3`) | everything except HOME OFFICE + GUEST (`!NotForIOT`) | any | DNS to `opt3ip`; the old IOT `pass any -> any` is disabled since 2026-10-19 (`utils/f2-opnsense-iot.sh`) |
| WireGuard `10.10.10.0/24` | IOT / APP / LAN | per rule | VPN |
| any CommonDNS member (LAN, IOT, GUEST, VPN, DMZ, APP) | a DNS server outside them | 53 | redirected to the router's own address on that interface (AdGuard); one rdr per interface since 2026-10-19 (`utils/f2-opnsense-dns.sh`) - AdGuard answers redirected UDP from the interface address, so a single rdr to `127.0.0.1` never got its replies back |
| WAN | WAN address | 443 | HAProxy → Grocery (F2-05 / F4) |

---

## DNS (A6)

| Name | Access |
|------|--------|
| `grocery.dkhomelabserver.xyz` | Public HTTPS (HAProxy backend `192.168.50.30`) |
| Other services | VPN-only (`10.10.10.x` WG) |

Zone: **`dkhomelabserver.xyz`**

---

## Dev vs prod summary

| | Dev | Prod |
|---|-----|------|
| Network | `192.168.122.0/24` | IOT 20 + APP 51 (QinQ) |
| VMs | libvirt `Proxmox` → `ubuntu-apps-dev` | `ubuntu-nas`, `ubuntu-apps` |
| Branch / GH | `homelab-v2` / dev | `main` / prod |

---

*Update homelab v2 MAC column after F3 VM creation.*
