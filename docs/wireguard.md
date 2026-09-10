# WireGuard — homelab v2

> **Status:** F2-04 as-built — `wg0` **`10.10.10.0/24`** :51820 on OPNsense.  
> **Related:** [opnsense-baseline.md](opnsense-baseline.md) (F2-04), [network.md](network.md)

## Decision (B3)

- **Primary remote access:** WireGuard on OPNsense
- **Public HTTPS:** only `grocery.dkhomelabserver.xyz` (HAProxy)
- Other services: **VPN-only**

## Addressing (as-built on router)

| Item | Value |
|------|-------|
| VPN subnet | **`10.10.10.0/24`** |
| OPNsense WG interface | **`10.10.10.1`** (`wg0`) |
| Listen port | `51820` |

## OPNsense setup (summary)

1. **VPN → WireGuard → Local**
   - Listen port: e.g. `51820/udp` (forward on WAN if behind CGNAT, use documented port)
   - Tunnel address: `10.10.10.1/24`
   - DNS: optional `192.168.20.1` or Pi-hole if added later

2. **Peers** — one per device (laptop, phone):
   - Generate keypair per client (never reuse private keys)
   - Allowed IPs for full homelab access: `192.168.20.0/24, 192.168.50.0/24, 10.10.10.0/24`
   - Or split: only subnets you need

3. **Firewall → WireGuard**
   - Allow WG net → LAN/IOT/APP as needed

4. **WAN**
   - Pass UDP listen port to OPNsense

## Client config template

Save as `homelab-wg-client.conf` ( **do not commit** — store in Bitwarden or password manager):

```ini
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address = 10.10.10.7/32
DNS = 192.168.20.1

[Peer]
PublicKey = <OPNSENSE_WG_PUBLIC_KEY>
PresharedKey = <optional>
Endpoint = <WAN_HOSTNAME_OR_IP>:51820
AllowedIPs = 192.168.20.0/24, 192.168.50.0/24, 10.10.10.0/24
PersistentKeepalive = 25
```

Import in WireGuard app (Linux: `sudo wg-quick up ./homelab-wg-client.conf`).

## Verification

```bash
# After connecting
ping 192.168.20.1    # OPNsense IOT
ping 192.168.20.20   # Proxmox (when online)
ping 192.168.50.30   # ubuntu-apps (F3+)
```

## Keys and backup

| Item | Storage |
|------|---------|
| OPNsense WG keys | OPNsense config backup (`config.xml`) |
| Client private keys | Bitwarden Secure Note per device |
| Preshared keys (if used) | Bitwarden |

WireGuard keys are **not** stored in GitHub Secrets.

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Handshake never completes | WAN UDP port forward, firewall, endpoint IP |
| Ping LAN fails | Peer Allowed IPs, OPNsense WG firewall rules |
| DNS fails | DNS setting in client Interface, OPNsense DNS resolver |

---

*Update endpoint hostname if dynamic DNS is used for WAN.*
