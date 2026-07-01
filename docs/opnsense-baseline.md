# OPNsense baseline — F2 sprint

> **Status:** F2 reference checklist — configure manually on the router (one-shot; not via GitHub Actions).  
> **Walkthrough:** [opnsense-ui-walkthrough.md](opnsense-ui-walkthrough.md)  
> **Verify:** `utils/f2-verify.sh`

**Goal:** router ready for F3 (Proxmox TF) and F4 (apps): VLANs, DHCP reservations, firewall, WireGuard, HAProxy for Grocery.

---

## F2 sprint — task overview

| ID | Task | Blocks F3? | Status |
|----|------|------------|--------|
| F2-01 | VLAN interfaces (IOT 20, APP 51) | yes | [x] as-built: IOT `.20.1`, APP QinQ gw `.50.50` |
| F2-02 | DHCP reservations (see [network.md](network.md)) | yes | [~] Proxmox `.20.20` on router; NAS/apps/HA at F3/F5 |
| F2-03 | Firewall: APP → NAS NFS | yes | [x] `opt6` → `.20.12` :2049/:111 (SSH 2026-07-01) |
| F2-04 | WireGuard VPN | recommended | [x] `wg0` `10.10.10.0/24` :51820 (as-built) |
| F2-05 | HAProxy + ACME `grocery.dkhomelabserver.xyz` | F4 public app | [ ] |
| F2-06 | Export / backup `config.xml` | F5 DR | [~] after each router change |
| F2-07 | Document actual MAC addresses | F3 | [ ] |

---

## F2-01 — VLAN interfaces

**OPNsense:** Interfaces → Assignments → VLANs → Parent (LAN/trunk port).

| VLAN tag | Name | IPv4 | Role |
|----------|------|------|------|
| 20 | IOT | 192.168.20.1/24 | Proxmox mgmt, HA, NAS |
| 51 | APP | **192.168.50.50/26** (QinQ) | Docker / `ubuntu-apps`; DHCP `.30`–`.62` |

Enable both interfaces; ensure trunk from switch carries tags 20 and 51 to Proxmox NIC1/NIC3.

**Definition of done:**

- [x] Ping `192.168.20.1` and `192.168.50.50` from laptop LAN
- [ ] Trunk/tags confirmed on switch + Proxmox NICs (manual)

---

## F2-02 — DHCP reservations

**OPNsense:** Services → DHCPv4 → [IOT / APP] → Static mappings.

Use the table in [network.md](network.md). Start with placeholder MACs; **F2-07** replaces with real MACs from Proxmox/VM console.

**Definition of done:**

- [x] Static mapping for Proxmox **`192.168.20.20`** (MAC on router)
- [ ] Static mappings for NAS `.20.12`, HA `.20.13`, apps `.50.30` (MAC at F3/F5)
- [ ] No duplicate IPs on LAN

---

## F2-03 — Firewall rules

Minimum for homelab v2:

### APP → IOT (NFS)

| Field | Value |
|-------|-------|
| Interface | APP |
| Protocol | TCP |
| Source | APP net |
| Destination | `192.168.20.12` |
| Port | 2049, 111 (optional rpcbind) |
| Action | Pass |

### WAN → HAProxy (later, with F2-05)

| Field | Value |
|-------|-------|
| Interface | WAN |
| Destination | WAN address |
| Port | 443 |
| Action | Pass → HAProxy |

Default deny on WAN for other inbound services.

**Definition of done:**

- [x] APP → NAS NFS rules on `opt6` (homelab-v2 marker in config)

---

## F2-04 — WireGuard

See **[wireguard.md](wireguard.md)** — as-built **`10.10.10.0/24`** on `wg0`.

**OPNsense:** VPN → WireGuard → Local instance + peers.

**Definition of done:**

- [ ] At least one peer (laptop/phone) connects
- [ ] VPN clients reach `192.168.20.0/24` and `192.168.50.0/24` as needed

---

## F2-05 — HAProxy + ACME (Grocery public)

**Domain:** `grocery.dkhomelabserver.xyz` (A record → WAN IP).

**OPNsense:**

1. System → Trust → ACME Client — register Let's Encrypt, issue cert for `grocery.dkhomelabserver.xyz`
2. Services → HAProxy → Settings — enable
3. Frontend: WAN :443, SSL, cert from ACME
4. Backend: `192.168.50.30:<grocery-port>` (exact port in F4 when Grocery stack is up)

Until F4, backend can point to a placeholder or remain disabled; cert and frontend can be prepared.

**Definition of done:**

- [ ] DNS resolves `grocery.dkhomelabserver.xyz` to WAN IP
- [ ] ACME cert issued (valid)
- [ ] HAProxy frontend listens on 443 (backend may be F4)

---

## F2-06 — Config backup

After any OPNsense change:

```bash
# From laptop (SSH key auth recommended)
OPNSENSE_HOST=192.168.1.1 ./utils/backup-opnsense-config.sh

# Or manual: System → Configuration → Backups → Download
# See: docs/opnsense-ui-walkthrough.md (F2-06)
```

Store copies:

- Local: `opnsense/backups/` (gitignored)
- Bitwarden: note "OPNsense config backup date"
- F5: automated copy to Purple / pCloud

**Definition of done:**

- [ ] At least one `config.xml` export saved outside the router
- [ ] [RESTORE.md](../opnsense/RESTORE.md) reviewed

---

## F2-07 — Real MAC addresses

Collect from Proxmox / VMs / T620 and update [network.md](network.md) + OPNsense DHCP mappings.

```bash
# Proxmox host
ip link show

# Or from OPNsense DHCP leases after first boot
```

**Definition of done:**

- [ ] Placeholder MACs replaced in `docs/network.md`
- [ ] DHCP reservations match hardware

---

## Out of scope (F2)

- Terraform / Ansible for OPNsense (manual baseline only)
- Full internal DNS (split-DNS) — optional backlog
- DMZ VLAN 50 — unused per A5

---

## F2 gate → F3

- [ ] F2-01 … F2-03 complete
- [ ] F2-06 backup taken
- [ ] WireGuard or LAN access to Proxmox **`192.168.20.20`** for TF/Ansible bootstrap

**Next:** F3 — Proxmox Terraform (`ubuntu-nas`, `ubuntu-apps`), prod runner `homelab-prod`.
