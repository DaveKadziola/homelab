---
name: Homelab greenfield dummy
overview: Greenfield homelab v2 — iteration.
todos:
  - id: security-audit-fixes
    content: "Prod audit 2026-10-20 (knowledge/security-audit-2026-10-20.md); replaces audit-final and security-audit-hosts. Closed 2026-10-23: S4 (Caddy terminates TLS, Authelia is plain HTTP behind it), S5, S9 (the 15 laptop copies shredded; the NAS keeps opnsense/config-*.xml daily), S11 (curl: Actual bootstrapped true, Trilium isInitialized true), S21 (OPNsense 26.7.7, pkg audit -q lists nothing), S26 (the noble-security packages came through unattended-upgrades; the noble-updates ones applied by hand, containerd restarted, no container restarted). Accepted: S12 (key only), S22 (nfs-root-squash). Agreed fixes, one item each: admins-alias, host-firewalls, pve-hardening, runner-key-cleanup, sshd-x11, trivy-daily, admin-certs. S7 from WireGuard and WAN goes with opnsense-wan-audit."
    status: in_progress
  - id: admins-alias
    content: "Operator 2026-10-23: OPNsense alias Admins (laptop and phone: fixed LAN leases and their WireGuard addresses); admin ports only from Admins. IOT gets DNS and NTP on the router, the NAS SSH to the router, Kuma (T620) and the runner what they use on APP; then IOT is blocked to the router, LAN and APP (S16). Router SSH key-only, from Admins and the NAS (S17). unbound 53530 blocked from clients, AdGuard 8443 from Admins only (S24). The APP .50.30 -> NAS SSH rule removed (S25). One router window, scripts with --dry-run and auto-revert."
    status: pending
  - id: host-firewalls
    content: "Operator 2026-10-23: firewall on ubuntu-nas and ubuntu-apps through Ansible, DEV first, with auto-revert (S6). Apps: published ports only from Caddy, Kuma (T620) and Admins (DOCKER-USER); Postgres 5432 only from Admins, Kuma and the Docker bridge (S1); Dozzle 8080 only from Caddy and Kuma, because the direct port bypasses Authelia (S2). NAS: SSH from Admins and the runner, 445 from LAN and WireGuard, NFS from apps and Proxmox (S24)."
    status: pending
  - id: pve-hardening
    content: "Operator 2026-10-23: TFA for root@pam; Terraform SSH by key, then PasswordAuthentication no (S18); PVE firewall with 22/8006 from Admins and the runner, overriding the default management set (S18, S24); X11Forwarding no (S27). Token: a role with the privileges the bpg provider needs, a new privsep=1 token tested on DEV, swap the secret, delete the old token after a real apply (S19). Console at hand."
    status: pending
  - id: runner-key-cleanup
    content: "S20 (operator 2026-10-23): Apps Deploy Prod writes the ubuntu-prod key to ~/.ssh/homelab_prod_ed25519 on CT 110 and leaves it there, where the next job on that runner (Infra Plan Prod of any PR into main) can read it. Remove it at the end of each job. Sudo stays: Ansible become needs it."
    status: pending
  - id: sshd-x11
    content: "S27 (operator 2026-10-23): X11Forwarding no on ubuntu-nas and ubuntu-apps through Ansible; Proxmox is in pve-hardening."
    status: pending
  - id: trivy-daily
    content: "S15 (operator 2026-10-23): Trivy scans the running images on ubuntu-apps every day and mails only when the list of HIGH and CRITICAL findings with a fix changes. Not a merge gate."
    status: pending
  - id: admin-certs
    content: "S23 (operator 2026-10-23, simplest way): Proxmox and Home Assistant renew their own Let's Encrypt certificate (DNS-01, a Cloudflare token per device). proxmox.dkhomelabserver.xyz:8006 serves the self-signed PVE certificate; the ACME certificate for it on OPNsense never reaches the host. The switch stays on HTTP, from Admins only."
    status: pending
  - id: ai-log-analysis
    content: "Package 2 (operator 2026-10-20): AI summaries through OpenRouter of cleaned audit results and logs (allowlist, aggregation); nothing raw into the public repo"
    status: pending
  - id: security-public-repo
    content: "2026-10-20: fork PRs need all_external_contributors, rulesets have no bypass, actions are pinned to SHAs (sha_pinning_required), CI threat model is in knowledge/security.md. Decision 2026-10-22: the house map leaves the public repo (public-map-split), then one history rewrite (git-history-state)."
    status: in_progress
  - id: app-network-access
    content: "Read 2026-10-22, rules not changed. APP (vlan07) has NFS and SSH to the NAS and a pass to everything except PrivateNetworks, so the whole VLAN reaches the internet, not one application. The separate WAN audit (WireGuard and Grocery only) is opnsense-wan-audit and waits until the end."
    status: pending
  - id: weekly-security-audit
    content: "Package 2 (operator 2026-10-20): a weekly audit on a timer — nmap S7 from IOT, versions, OPNsense rules (images: trivy-daily) — report by mail and on the NAS, never in public-repo artifacts"
    status: pending
  - id: ubuntu-2604
    content: "Deferred by the operator 2026-10-23. After release PR #78 (operator 2026-10-21): move the apps and NAS VMs from Ubuntu 24.04 to 26.04 — DEV first, with a rebuild and restore drill, then prod as its own release. Changing the image (terraform/environments/*/terraform.tfvars image_url) is likely a VM replacement (risk gate). It does not fix rclone: 26.04 still ships 1.60.1 in apt, so tools stay pinned to an upstream version"
    status: pending
  - id: homarr-dashboard-widgets
    content: "Not implemented. homarr_board.py writes only an application tile. Homarr image 2.6.0 had no options schema for weather or a clock. Nothing was guessed."
    status: pending
  - id: public-map-split
    content: "Operator 2026-10-22: the public repo stays a portfolio (architecture, how deploy works). The house map (addresses, domain, mail) moves to gitignored docs and/or a module from a private repo. Current files have to be rewritten with example addresses. Do not touch history yet: one rewrite is git-history-state, after this swap, not before."
    status: pending
  - id: git-history-state
    content: "After public-map-split (operator 2026-10-22): remove terraform/terraform.tfstate and terraform/terraform.tfstate.backup from the whole history (added in 18dd8c6, removed in ce25d3a; six 192.168 addresses, no passwords) and the old house map. One history rewrite, force-push main and homelab-v2. git-filter-repo is not installed. After that every clone is stale; GitHub can keep old objects until it purges them. Do not do this before the files are swapped, or the map comes back in new commits."
    status: pending
  - id: opnsense-wan-audit
    content: "Last (operator 2026-10-22): audit OPNsense rules. Only WireGuard and Grocery should leave on WAN. Read the rules, compare with docs/network.md (WAN 443/tcp and 51820/udp). Do not change the configuration until the audit shows a difference and the operator accepts it. Includes S7 from WireGuard and WAN (a scan from outside, e.g. a phone hotspot)."
    status: pending
  - id: subnet-refactor
    content: "At the very end, after opnsense-wan-audit (operator 2026-10-22): subnet refactor. The operator thinks the VLAN layout can be better. There is no design yet. Change nothing until a layout is approved."
    status: pending
isProject: false
---

# Homelab plan

Open work (pending and in progress) is the frontmatter of this file. Move an item to
[`greenfield-completed.md`](greenfield-completed.md) when it is done. The June and July notes are in
[`greenfield-notes.md`](greenfield-notes.md) and are not a procedure.
