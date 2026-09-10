# Networking

Canonical map and “do not renumber” list: [`docs/network.md`](../network.md). This page is the operator view.

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
| APP 51 (QinQ) | `192.168.50.50/26` | apps `.50.30` |
| WireGuard | `10.10.10.1/24` | port `51820` |

Occupied forever: printer `.20.10`, Zoom `.20.11`, Tuya `.20.50–.58`, legacy NPM `.50.2`.

PVE has **one** host IP on NIC1. NIC2 = disk passthrough to NAS. NIC3 = APP trunk.

## Exposure

| Path | What |
|------|------|
| LAN / VPN only | Almost every UI (Portainer, Immich, Authelia, …) |
| Public HTTPS | Grocery `grocery.dkhomelabserver.xyz` via OPNsense HAProxy (prod, after F4 sign-off) |

Postgres `:5432` is published on the apps host — intended for grocery/`host.docker.internal` on DEV. Do not publish it to WAN. F9 will re-audit this.

## Related

- [`docs/opnsense-baseline.md`](../opnsense-baseline.md)
- [`docs/wireguard.md`](../wireguard.md)
