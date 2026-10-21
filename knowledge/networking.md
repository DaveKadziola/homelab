# Networking

Canonical map and “do not renumber” list: [`docs/network.md`](../docs/network.md). This page is the operator view.

## Dev

- Isolated libvirt `default`: `192.168.122.0/24`, GW `.1`
- Apps: **`192.168.122.50`**
- No OPNsense, no VLANs, no public DNS
- App names `<app>.dev.dkhomelabserver.xyz` and the Authelia portal `auth.dev.dkhomelabserver.xyz` go through Caddy on `192.168.122.50` ([decision 0007](decisions/0007-app-names-caddy-authelia.md)). They resolve through the AdGuard rewrites once `utils/f2-adguard-rewrites.sh` has run (owner's decision); until then add them on the **client**:

  ```
  192.168.122.50 auth.dev.dkhomelabserver.xyz homarr.dev.dkhomelabserver.xyz
  ```

  Hitting the raw IP reaches the app's own port but no Authelia session: the cookie domain is `dev.dkhomelabserver.xyz` (`config/services.yml` `environments.dev.domain`).

## Prod (as-built, do not invent new IPs)

| VLAN | Gateway | Homelab slots |
|------|---------|----------------|
| IOT 20 | `192.168.20.1` | PVE `.20.20` · NAS `.20.12` · HA `.20.13` |
| APP 51 (`vlan07`, 802.1Q) | `192.168.50.50/26` | apps `.50.30` |
| WireGuard | `10.10.10.1/24` | port `51820` |

Occupied forever: printer `.20.10`, Zoom `.20.11`, Tuya `.20.50–.58`. Legacy NPM `.50.2` is gone (2026-10-19, `docs/network.md`).

PVE has **one** host IP: `vmbr0.20` on `bond0` (nic0 + nic1 backup since 2026-10-21, CRC errors on nic1); nic2 reserved for APP. Switch ports deliver IOT as VLAN 20 **tagged** (`docs/network.md`). Exception: the T620 port is untagged VLAN 20, PVID 20 (2026-10-20); its Realtek `r8169` NIC stalled with `NETDEV WATCHDOG: transmit queue 0 timed out` as soon as HAOS ran a VLAN 20 interface.

## Exposure

| Path | What |
|------|------|
| LAN, WireGuard, IOT | Every app port on `ubuntu-apps` `192.168.50.30` and, with profile `proxy`, every app name through Caddy + Authelia. IOT reaching them is finding S16 ([`security-audit-2026-10-20.md`](security-audit-2026-10-20.md)); WireGuard follows the `docs/network.md` firewall table and was not scanned. APP itself reaches only the internet and the NAS NFS |
| LAN + WireGuard only | SMB `445` on the NAS `192.168.20.12` (shares `share`, `media`); limited by Samba `hosts allow`, because IOT devices share the NAS subnet and the router cannot filter them ([`storage.md`](storage.md#samba)) |
| Public HTTPS | Grocery `grocery.dkhomelabserver.xyz` via OPNsense HAProxy (prod) |
| OPNsense WAN | Passes only TCP 443 (HAProxy) and UDP 51820 (WireGuard) since 2026-10-20; TCP 80 reached the AdGuard Home login and is closed (`docs/network.md`). Whether the ISP router in front forwards them is not visible from inside |

Postgres `:5432` is published on the apps host — intended for grocery/`host.docker.internal` on DEV. Do not publish it to WAN. The F9 audit found it open from LAN and IOT on prod (S1, [`security-audit-2026-10-20.md`](security-audit-2026-10-20.md)).

## Related

- [`docs/opnsense-baseline.md`](../docs/opnsense-baseline.md)
- [`docs/wireguard.md`](../docs/wireguard.md)
