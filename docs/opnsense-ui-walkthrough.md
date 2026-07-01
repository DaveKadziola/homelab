# OPNsense UI walkthrough — F2 sprint

> Step-by-step for **OPNsense web UI**. English labels match default OPNsense menus.  
> **Checklist:** [opnsense-baseline.md](opnsense-baseline.md)  
> **Verify from laptop:** `utils/f2-verify.sh`

Access: `https://192.168.1.1` or `https://192.168.20.1` (your LAN/IOT gateway).

---

## F2-01 — VLAN interfaces (IOT 20, APP 51)

1. **Interfaces → Assignments → VLANs → +**
   - Parent: trunk/LAN port (the interface carrying tagged traffic to Proxmox)
   - VLAN tag: `20` → Save
   - Repeat for tag `51`
2. **Interfaces → Assignments**
   - Add `vlan0.20` (or similar) → Description `IOT` → Save
   - Add `vlan0.51` → Description `APP` → Save
3. **Interfaces → [IOT]**
   - Enable, IPv4: Static, `192.168.20.1/24`
   - Block private networks: **off** on internal VLANs if needed for routing
4. **Interfaces → [APP]**
   - Enable, IPv4: Static, `192.168.50.1/24`
5. **Save → Apply changes**

**Verify:** `./utils/f2-verify.sh` — ping `192.168.20.1` and `192.168.50.1`

---

## F2-02 — DHCP reservations

**Services → DHCPv4 → [IOT]** (interface with `192.168.20.0/24`)

| Description | IP | MAC (replace placeholder) |
|-------------|-----|---------------------------|
| proxmox | 192.168.20.10 | from `utils/collect-homelab-macs.sh` |
| homeassistant | 192.168.20.11 | T620 NIC |
| ubuntu-nas | 192.168.20.12 | VM MAC after F3 or planned |
| (optional) | | |

**Services → DHCPv4 → [APP]** (`192.168.50.0/24`)

| Description | IP | MAC |
|-------------|-----|-----|
| ubuntu-apps | 192.168.50.30 | VM MAC after F3 |

Enable DHCP server on each interface if not already (range e.g. `.100–.200` per [network.md](network.md)).

---

## F2-03 — Firewall

**Firewall → Rules → APP** (or floating if you use shared rules)

1. **Pass** — TCP — Source: APP net — Dest: `192.168.20.12` — Dest port: `2049` — Description `NFS apps to NAS`
2. Optional: same for port `111` (rpcbind)
3. **Firewall → Rules → WAN**
   - Pass TCP 443 to WAN address (for HAProxy, F2-05)
   - Default: block all other inbound

**Firewall → Settings → Advanced** — ensure inter-VLAN routing is allowed where needed.

---

## F2-04 — WireGuard

See [wireguard.md](wireguard.md). Summary:

1. **VPN → WireGuard → Local** — Create instance, listen UDP `51820`, tunnel `10.0.0.1/24`
2. **VPN → WireGuard → Endpoints** — add peer(s), generate keys
3. **Firewall → WireGuard** — allow WG net → LAN/IOT/APP
4. **Firewall → WAN** — Pass UDP `51820` to OPNsense

Export client config from peer UI → store in Bitwarden.

---

## F2-05 — HAProxy + ACME (Grocery)

**SSH scripts:**

```bash
OPNSENSE_HOST=192.168.1.1 ./utils/f2-opnsense-apply.sh      # F2-03 NFS + backup
OPNSENSE_HOST=192.168.1.1 ./utils/f2-opnsense-f05.sh        # F2-05 ACME grocery + HAProxy enable
```

**Prerequisite:** DNS A record `grocery.dkhomelabserver.xyz` → WAN public IP (script prints `ifconfig.me`).

1. **Services → HAProxy → Settings** — Enable HAProxy
2. **System → Trust → ACME Client**
   - Add account (Let's Encrypt)
   - Add certificate: domain `grocery.dkhomelabserver.xyz`, validation HTTP-01 or DNS (as supported)
   - Issue certificate
3. **Services → HAProxy → Real Servers** — Backend `grocery`, `192.168.50.30`, port TBD (F4)
4. **Frontend** — WAN `443`, SSL, cert from ACME, default backend `grocery`
5. **WAN firewall** — allow 443 (F2-03)

Until F4: backend can be a maintenance page or disabled; cert + frontend can still be tested.

---

## F2-06 — Config backup

**UI:** System → Configuration → Backups → Download

**SSH** (after enabling Secure Shell + your key):

```bash
OPNSENSE_HOST=192.168.20.1 ./utils/backup-opnsense-config.sh
```

Store under `opnsense/backups/` (gitignored) and note date in Bitwarden.

---

## F2-07 — MAC addresses

```bash
./utils/collect-homelab-macs.sh
```

Edit [network.md](network.md) — replace `aa:bb:cc:dd:ee:0x` placeholders.

---

## F2 gate → F3

When done:

- [ ] `./utils/f2-verify.sh` — gateways OK
- [ ] DHCP reservations entered (MACs real or updated after F3)
- [ ] At least one `config.xml` backup
- [ ] WireGuard OR LAN route to future Proxmox `192.168.20.10`

Mark checkboxes in [opnsense-baseline.md](opnsense-baseline.md).
