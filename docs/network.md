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
| APP | 51 | vlan07 (802.1Q on igc2; was QinQ `qinq01` on vlan06 until 2026-10-19) | **`192.168.50.50/26`** | Docker; DHCP **off** (range `.30`–`.62` configured but disabled; VMs use static IPs from cloud-init) |
| WireGuard | — | wg0 | **`10.10.10.1/24`** | port `51820`; not `10.0.0.0` |
| VPN (legacy VLAN) | 40 | vlan05 | `10.0.0.1/28` | separate from WG |

### Already occupied on IOT (do not change)

| IP | Device |
|----|--------|
| `192.168.20.10` | Canon printer |
| `192.168.20.11` | E1 Zoom |
| `192.168.20.20` | **Proxmox host** (mgmt `vmbr0.20`) |
| `192.168.20.50`–`.58` | Tuya / IoT |

### Homelab v2 slots (new DHCP static mappings at F3/F5)

| Role | VLAN | Tag | IP | MAC |
|------|------|-----|-----|-----|
| Proxmox host (`proxmox.dkhomelabserver.xyz`) | IOT | 20 | **`192.168.20.20`** | `3c:49:37:19:71:ae` (nic1, Intel igb; on router since 2026-10-19) |
| `ubuntu-nas` | IOT | 20 | **`192.168.20.12`** | VM NIC — set at F3 |
| HP T620 HAOS | IOT | 20 | **`192.168.20.13`** | `7c:d3:0a:1a:f5:10` (on router; confirmed 2026-10-20: HAOS `network info` on the T620 shows it and DHCP gives `.20.13`) |
| `ubuntu-apps` | APP | 51 | **`192.168.50.30`** | VM NIC — set at F3 |

**DMZ** (VLAN 50, `vlan06`, plain 802.1Q since APP left QinQ): `192.168.50.65/28` (`.64`–`.79`) since 2026-10-19, moved out of APP `192.168.50.0/26` (`utils/f2-opnsense-dmz.sh`). Unused; DHCP off. The dead legacy NPM `.50.2` (no ARP) lost its static map and its LAN/DMZ rules and its WAN port-forward (disabled).

---

## Proxmox — 3× NIC (one host IP)

As-built 2026-10-19 (PVE 9.2.2, `proxmox.dkhomelabserver.xyz`, interface names pinned):

| NIC | MAC | Role |
|-----|-----|------|
| `nic1` Intel igb | `3c:49:37:19:71:ae` | `bond0` primary -> `vmbr0` (VLAN-aware) |
| `nic0` Realtek r8169 | `70:85:c2:53:e0:ac` | `bond0` backup (active-backup, takes over when `nic1` loses link; failover tested) |
| `nic2` Intel igb | `3c:49:37:19:71:af` | `vmbr1` (VLAN-aware, no host IP) -> APP VLAN 51 -> `ubuntu-apps` `.50.30` |

Management is `vmbr0.20` = **`192.168.20.20/24`**, gateway `.20.1`. The switch ports deliver IOT as **VLAN 20 tagged**: untagged, the host got no ARP replies (and the installer no DHCP ACK). Exception: the T620 port is **untagged** VLAN 20, PVID 20 (2026-10-20); its Realtek `r8169` NIC stalled with `NETDEV WATCHDOG: transmit queue 0 timed out` as soon as HAOS ran a VLAN 20 interface. `bond0` has a fixed MAC `3c:49:37:19:71:ae` (`hwaddress`; otherwise it takes the first enslaved NIC's MAC, which changed after an `ifreload`). APP is a plain **VLAN 51** on the router trunk (`vlan07` on `igc2`, 802.1Q) since 2026-10-19, no longer QinQ inside VLAN 50 (`utils/f2-opnsense-app-vlan.sh`); the GS308EP carries VLAN 51 tagged to the router and `nic2` ports. Probe with ARP, not ping: DMZ/APP have no rule that passes ICMP to the router. SA500 + Purple go to the NAS VM as disks (by-id), not through a NIC. The host file is `config/pve/interfaces.prod`; `utils/pve-network.py --env prod` writes it with an auto-revert (write path not run on a host yet).

Host names come from **AdGuard Home rewrites** on OPNsense (`/usr/local/AdGuardHome/AdGuardHome.yaml`, `filtering.rewrites`): `proxmox.dkhomelabserver.xyz` -> `.20.20`, `hass.dkhomelabserver.xyz` -> `.20.13` (moved from `.20.20` on 2026-10-19), `adguard.` -> `192.168.1.1`, `ap.` -> `.1.3`, `switch.` -> `.1.2`; `npm.` disabled (NPM removed); `nas.dkhomelabserver.xyz` -> `192.168.20.12` (Samba clients, `\\nas.dkhomelabserver.xyz\share`, added 2026-10-19).

---

## Cross-VLAN firewall (F2)

| Source | Destination | Ports | Purpose |
|--------|-------------|-------|---------|
| APP net `192.168.50.0/26` (`opt6`) | `192.168.20.12` | TCP 2049, 111 | NFS apps → NAS. Until 2026-10-19 both rules carried the port in a top-level `<destinationport>`, which pf ignores, so APP reached every TCP port of the NAS (`pfctl -sr`: `pass ... to 192.168.20.12` with no port). Fixed on the router by `utils/f2-opnsense-nas-ports.sh` (port in `<destination><port>`; pf now shows `port = nfsd` / `port = sunrpc`); the generator `utils/f2-opnsense-apply-remote.sh` is fixed the same way |
| `192.168.50.30/32` (`opt6`) | `192.168.20.12` | TCP 22 | Added by `utils/f2-opnsense-nas-ports.sh` on 2026-10-19 for a prod runner on `ubuntu-apps`. Unused since the runner moved to the LXC `ci-runner` on IOT (2026-10-20), which reaches the NAS without the router; remove with the next router change |
| LAN `192.168.1.0/24`, WireGuard `10.10.10.0/24` | `192.168.20.12` | TCP 445 | Samba on the NAS. Enforced by Samba `hosts allow` (`config/storage.yml`): IOT devices share the NAS subnet and the router cannot filter them |
| IOT (`opt3`) | everything except HOME OFFICE + GUEST (`!NotForIOT`) | any | DNS to `opt3ip`; the old IOT `pass any -> any` is disabled since 2026-10-19 (`utils/f2-opnsense-iot.sh`) |
| WireGuard `10.10.10.0/24` | IOT / APP / LAN | per rule | VPN |
| APP net (`opt6`) | everything except `PrivateNetworks` | any | internet for `ubuntu-apps` (images, apt, runner, rclone) since 2026-10-19 (`utils/f2-opnsense-app-egress.sh`); private networks stay closed except the NAS rules above |
| any CommonDNS member (LAN, IOT, GUEST, VPN, DMZ, APP) | a DNS server outside them | 53 | redirected to the router's own address on that interface (AdGuard); one rdr per interface since 2026-10-19 (`utils/f2-opnsense-dns.sh`) - AdGuard answers redirected UDP from the interface address, so a single rdr to `127.0.0.1` never got its replies back |

**DNS rule of thumb:** a client must use the router address **on its own VLAN** as resolver (APP: `192.168.50.50`, IOT: `.20.1`, LAN: `.1.1`). AdGuard answers a UDP query sent to another VLAN's router address from its own VLAN's address, and the client drops it.
| WAN | WAN address | 443 | HAProxy → Grocery (F2-05 / F4) |
| WAN | WAN address | UDP 51820 | WireGuard |
| WAN | WAN address | ~~TCP 80~~ | **Closed 2026-10-20** (`utils/f2-opnsense-wan-http.sh`): the rule passed to the firewall itself, where AdGuard Home listens on `*:80`, so its login page answered from WAN. Nothing needs it: HAProxy serves only 443 and every ACME certificate uses DNS-01 |

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
| Network | `192.168.122.0/24` | IOT 20 + APP 51 (802.1Q) |
| VMs | libvirt `Proxmox` → `ubuntu-apps-dev` | `ubuntu-nas`, `ubuntu-apps` |
| Branch / GH | `homelab-v2` / dev | `main` / prod |

---

*Update homelab v2 MAC column after F3 VM creation.*
