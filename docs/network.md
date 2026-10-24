# Network map — homelab v2

> **Status:** as-built, aligned with OPNsense; router rules last read 2026-10-20 (`pfctl -sr`, `pfctl -sn`).  
> **Related:** [opnsense-baseline.md](opnsense-baseline.md), greenfield plan.

## Dev pool (laptop only — no OPNsense)

| Role | Network | IP |
|------|---------|-----|
| libvirt `default` | `192.168.122.0/24` | GW `192.168.122.1` |
| **Dev** | `192.168.122.0/24` (nested PVE) | DHCP/static `.122.50` |
| `ubuntu-apps-dev` (TF) | same | **`192.168.122.50`** |
| GH branch | `develop` | env **dev** |

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
| `ubuntu-nas` | IOT | 20 | **`192.168.20.12`** | not needed: static IP from cloud-init (`terraform/environments/prod/terraform.tfvars`) |
| HP T620 HAOS | IOT | 20 | **`192.168.20.13`** | `7c:d3:0a:1a:f5:10` (on router; confirmed 2026-10-20: HAOS `network info` on the T620 shows it and DHCP gives `.20.13`) |
| `ubuntu-apps` | APP | 51 | **`192.168.50.30`** | not needed: static IP from cloud-init (`terraform/environments/prod/terraform.tfvars`) |

**DMZ** (VLAN 50, `vlan06`, plain 802.1Q since APP left QinQ): `192.168.50.65/28` (`.64`–`.79`) since 2026-10-19, moved out of APP `192.168.50.0/26` (`utils/opnsense-dmz.sh`). Unused; DHCP off. The dead legacy NPM `.50.2` (no ARP) lost its static map and its LAN/DMZ rules and its WAN port-forward (disabled).

---

## Proxmox — 3× NIC (one host IP)

As-built 2026-10-19 (PVE 9.2.2, `proxmox.dkhomelabserver.xyz`, interface names pinned):

| NIC | MAC | Role |
|-----|-----|------|
| `nic1` Intel igb | `3c:49:37:19:71:ae` | `bond0` -> `vmbr0` (VLAN-aware); backup since 2026-10-21, while it receives frames with CRC errors (`knowledge/troubleshooting.md`) |
| `nic0` Realtek r8169 | `70:85:c2:53:e0:ac` | `bond0` primary since 2026-10-21 (active-backup, the other slave takes over on link loss; failover tested) |
| `nic2` Intel igb | `3c:49:37:19:71:af` | `vmbr1` (VLAN-aware, no host IP) -> APP VLAN 51 -> `ubuntu-apps` `.50.30` |

`nic1` and `nic2` are the two ports of one Intel 82575EB card (PCI `04:00.0` / `04:00.1`).

Management is `vmbr0.20` = **`192.168.20.20/24`**, gateway `.20.1`. The switch ports deliver IOT as **VLAN 20 tagged**: untagged, the host got no ARP replies (and the installer no DHCP ACK). Exception: the T620 port is **untagged** VLAN 20, PVID 20 (2026-10-20); its Realtek `r8169` NIC stalled with `NETDEV WATCHDOG: transmit queue 0 timed out` as soon as HAOS ran a VLAN 20 interface. `bond0` has a fixed MAC `3c:49:37:19:71:ae` (`hwaddress`; otherwise it takes the first enslaved NIC's MAC, which changed after an `ifreload`). APP is a plain **VLAN 51** on the router trunk (`vlan07` on `igc2`, 802.1Q) since 2026-10-19, no longer QinQ inside VLAN 50 (`utils/opnsense-app-vlan.sh`); the GS308EP carries VLAN 51 tagged to the router and `nic2` ports. Probe with ARP, not ping: DMZ/APP have no rule that passes ICMP to the router. SA500 + Purple go to the NAS VM as disks (by-id), not through a NIC. The host file is `config/pve/interfaces.prod`; `utils/pve-network.py --env prod` writes it with an auto-revert (write path not run on a host yet).

Host names come from **AdGuard Home rewrites** on OPNsense (`/usr/local/AdGuardHome/AdGuardHome.yaml`, `filtering.rewrites`): `proxmox.dkhomelabserver.xyz` -> `.20.20`, `hass.dkhomelabserver.xyz` -> `.20.13` (moved from `.20.20` on 2026-10-19), `kuma.dkhomelabserver.xyz` -> `.20.13` (Uptime Kuma on `:3001`, added 2026-10-22), `adguard.` -> `192.168.1.1`, `ap.` -> `.1.3`, `switch.` -> `.1.2`; `npm.` disabled (NPM removed); `nas.dkhomelabserver.xyz` -> `192.168.20.12` (Samba clients, `\\nas.dkhomelabserver.xyz\share`, added 2026-10-19). `grocery.dkhomelabserver.xyz` -> `192.168.100.2` (2026-10-20): HAProxy listens on the OPNsense WAN address, and the ISP router in front does no hairpin NAT, so from home the public answer `77.252.246.65` timed out.

Plain DNS cannot bypass AdGuard: port forwards on LAN (`igc2`), IOT (`vlan03`), GUEST (`vlan04`), VPN (`vlan05`), DMZ (`vlan06`) and APP (`vlan07`) send TCP/UDP 53 for any address outside the `CommonDNS` alias to the router's own address on that interface (`pfctl -sn`, 2026-10-20). `dig @1.1.1.1` from home therefore shows the AdGuard rewrites, not the public records; check those over DNS over HTTPS, e.g. `curl -H 'accept: application/dns-json' 'https://cloudflare-dns.com/dns-query?name=grocery.dkhomelabserver.xyz&type=A'` (public: `77.252.246.65`).

---

## Cross-VLAN firewall (F2)

| Source | Destination | Ports | Purpose |
|--------|-------------|-------|---------|
| APP net `192.168.50.0/26` (`opt6`) | `192.168.20.12` | TCP 2049, 111 | NFS apps → NAS; 111 is dropped by the NAS firewall since 2026-10-24 (NFS v4.2 needs only 2049). Until 2026-10-19 both rules carried the port in a top-level `<destinationport>`, which pf ignores, so APP reached every TCP port of the NAS (`pfctl -sr`: `pass ... to 192.168.20.12` with no port). Fixed on the router by `utils/opnsense-nas-ports.sh` (port in `<destination><port>`; pf now shows `port = nfsd` / `port = sunrpc`); the generator `utils/opnsense-apply-remote.sh` is fixed the same way |
| LAN `192.168.1.0/24`, WireGuard `10.10.10.0/24` | `192.168.20.12` | TCP 445 | Samba on the NAS. Enforced on the NAS by Samba `hosts allow` and the host firewall (`config/storage.yml` `firewall`, since 2026-10-24): IOT devices share the NAS subnet and the router cannot filter them |
| IOT (`opt3`) | the router (`opt3ip`) | UDP/TCP 53, UDP 123, ICMP echo | DNS, NTP and ping for every IOT device (the NAS backup pings the router first). Since 2026-10-24 (`utils/opnsense-lockdown.sh iot`, audit S16) |
| NAS `192.168.20.12` | the router (`opt3ip`) | TCP 22 | `config.xml` backup with the forced-command key |
| NAS, Home Assistant, Proxmox (`BeszelAgentsIot`) | apps `192.168.50.30` | TCP 8090 | Beszel agents connect to the hub |
| NAS `192.168.20.12` | apps `192.168.50.30` | TCP 2283 | photo watcher asks Immich to scan |
| Proxmox `192.168.20.20` | apps `192.168.50.30` | TCP 22 | NIC error mail over SSH (forced command) |
| T620 `.20.13`, prod runner `.20.14` (`AppCheckersIot`) | apps `192.168.50.30` | TCP any | Uptime Kuma checks; post-deploy tests |
| T620 `192.168.20.13` | WAN address `192.168.100.2` | TCP 443 | Kuma checks public Grocery through the AdGuard rewrite |
| IOT (`opt3`) | everything except `PrivateNetworks` | any | internet only; anything else from IOT is blocked and logged. Until 2026-10-24 the rule was `!NotForIOT`, so IOT reached the router, LAN and every app port (`pfctl -sr`, 2026-10-20). Devices on IOT still share L2 with Proxmox, the NAS and HA, which the router cannot filter |
| LAN, WireGuard, unless the source is in `Admins` | Proxmox, NAS, apps (`HomelabServers`) | `AdminPorts`: 22, 111, 2049, 3128, 5050, 5432, 8006, 8080, 9000, 9443 | blocked and logged since 2026-10-24 (`utils/opnsense-lockdown.sh admins`). `Admins` = laptop `192.168.1.20`, S23 `192.168.1.21` (static DHCP leases) and their WireGuard peers `10.10.10.2`-`.5`. Router GUI and SSH stay open on LAN (anti-lockout) |
| LAN, WireGuard, unless the source is in `Admins` | the router | TCP 80, 8443 (`RouterUiPorts`) | AdGuard Home UI, blocked and logged |
| every client interface (floating) | the router | TCP/UDP 53530 | unbound, blocked: it answers without the AdGuard filter (audit S24); AdGuard reaches it on `127.0.0.1` |
| WireGuard `10.10.10.0/24` | IOT / APP / LAN | any, except the blocks above | VPN |
| APP net (`opt6`) | everything except `PrivateNetworks` | TCP 80, 443, 587, 22000, 22067; UDP 123, 22000; ICMP echo | internet for `ubuntu-apps` (images, apt, mail, Syncthing, rclone) since 2026-10-24 (`utils/opnsense-app-egress.sh`, from the pf states of that day); anything else from APP is blocked and logged. Private networks stay closed except the NAS rules above. The unused `.50.30 -> NAS` SSH rule is gone (audit S25) |
| any CommonDNS member (LAN, IOT, GUEST, VPN, DMZ, APP) | a DNS server outside them | 53 | redirected to the router's own address on that interface (AdGuard); one rdr per interface since 2026-10-19 (`utils/opnsense-dns.sh`) - AdGuard answers redirected UDP from the interface address, so a single rdr to `127.0.0.1` never got its replies back |
| WAN | WAN address | 443 | HAProxy → Grocery (F2-05 / F4) |
| WAN | WAN address | UDP 51820 | WireGuard |
| WAN | WAN address | ~~TCP 80~~ | **Closed 2026-10-20** (`utils/opnsense-wan-http.sh`): the rule passed to the firewall itself, where AdGuard Home listens on `*:80`, so its login page answered from WAN. Nothing needs it: HAProxy serves only 443 and every ACME certificate uses DNS-01 |

**DNS rule of thumb:** a client must use the router address **on its own VLAN** as resolver (APP: `192.168.50.50`, IOT: `.20.1`, LAN: `.1.1`). AdGuard answers a UDP query sent to another VLAN's router address from its own VLAN's address, and the client drops it.

---

## DNS (A6)

| Name | Access |
|------|--------|
| `grocery.dkhomelabserver.xyz` | Public HTTPS (HAProxy backend `192.168.50.30`) |
| Other services | Home network only: LAN, WireGuard and IOT reach `192.168.50.30:<port>` (IOT: finding S16, [security-audit-2026-10-20](../knowledge/security-audit-2026-10-20.md)); names `<app>.dkhomelabserver.xyz` through Caddy + Authelia once the AdGuard rewrites exist ([decision 0007](../knowledge/decisions/0007-app-names-caddy-authelia.md)) |

Zone: **`dkhomelabserver.xyz`** - on Cloudflare (NS `jose.ns.cloudflare.com`, `vivienne.ns.cloudflare.com`). `grocery` is a DNS-only A record to the ISP public address (DNS over HTTPS 2026-10-20: `77.252.246.65`, equal to `curl https://api.ipify.org`); nothing on the router updates it.

---

## Dev vs prod summary

| | Dev | Prod |
|---|-----|------|
| Network | `192.168.122.0/24` | IOT 20 + APP 51 (802.1Q) |
| VMs | libvirt `Proxmox` → `ubuntu-apps-dev` | `ubuntu-nas`, `ubuntu-apps` |
| Branch / GH | `develop` / dev | `main` / prod |
