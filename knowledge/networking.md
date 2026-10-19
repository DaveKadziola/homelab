# Networking

Canonical map and “do not renumber” list: [`docs/network.md`](../docs/network.md). This page is the operator view.

## Dev

- Isolated libvirt `default`: `192.168.122.0/24`, GW `.1`
- Apps: **`192.168.122.50`**
- No OPNsense, no VLANs, no public DNS
- Authelia cookie domain is `homelab.local` — add on the **client**:

  ```
  192.168.122.50 authelia.homelab.local homelab.local
  ```

  Hitting the raw IP reaches the UI but first-factor / session fails (`no configured session cookie domain`).

## Prod (as-built, do not invent new IPs)

| VLAN | Gateway | Homelab slots |
|------|---------|----------------|
| IOT 20 | `192.168.20.1` | PVE `.20.20` · NAS `.20.12` · HA `.20.13` |
| APP 51 (`vlan07`, 802.1Q) | `192.168.50.50/26` | apps `.50.30` |
| WireGuard | `10.10.10.1/24` | port `51820` |

Occupied forever: printer `.20.10`, Zoom `.20.11`, Tuya `.20.50–.58`. Legacy NPM `.50.2` is gone (2026-10-19, `docs/network.md`).

PVE has **one** host IP: `vmbr0.20` on `bond0` (nic1 + nic0 backup); nic2 reserved for APP. Switch ports deliver IOT as VLAN 20 **tagged** (`docs/network.md`). Exception: the T620 port is untagged VLAN 20, PVID 20 (2026-10-20); its Realtek `r8169` NIC stalled with `NETDEV WATCHDOG: transmit queue 0 timed out` as soon as HAOS ran a VLAN 20 interface.

## Exposure

| Path | What |
|------|------|
| LAN / VPN only | Almost every UI (Portainer, Immich, Authelia, …) |
| LAN + WireGuard only | SMB `445` on the NAS `192.168.20.12` (shares `share`, `media`); limited by Samba `hosts allow`, because IOT devices share the NAS subnet and the router cannot filter them ([`storage.md`](storage.md#samba)) |
| Public HTTPS | Grocery `grocery.dkhomelabserver.xyz` via OPNsense HAProxy (prod, after F4 sign-off) |

Postgres `:5432` is published on the apps host — intended for grocery/`host.docker.internal` on DEV. Do not publish it to WAN. F9 will re-audit this.

## Related

- [`docs/opnsense-baseline.md`](../docs/opnsense-baseline.md)
- [`docs/wireguard.md`](../docs/wireguard.md)
