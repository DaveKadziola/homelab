---
name: Homelab greenfield dummy
overview: Greenfield homelab v2 — iteration.
todos:
  - id: audit-final
    content: "Prod audit 2026-10-20 (knowledge/security-audit-2026-10-20.md): S7 from LAN/IOT/APP done; left: scan from WireGuard and WAN, fixes S16-S27 (each one needs consent)"
    status: in_progress
  - id: ai-log-analysis
    content: "Package 2 (operator 2026-10-20): AI summaries through OpenRouter of cleaned audit results and logs (allowlist, aggregation); nothing raw into the public repo"
    status: pending
  - id: docs-diagrams
    content: "Later (operator 2026-10-20): draw.io diagrams — change flow (homelab-v2 to DEV, main to prod, approvals), network (VLANs, firewall, ports), backups"
    status: pending
  - id: security-public-repo
    content: "2026-10-20: fork PRs need all_external_contributors, rulesets have no bypass, actions are pinned to SHAs (sha_pinning_required), CI threat model is in knowledge/security.md. Decision 2026-10-22: the house map leaves the public repo (public-map-split), then one history rewrite (git-history-state)."
    status: in_progress
  - id: security-audit-hosts
    content: "Prod audit 2026-10-20 is written (knowledge/security-audit-2026-10-20.md, S16-S27); each fix is separate and needs consent"
    status: in_progress
  - id: app-network-access
    content: "Read 2026-10-22, rules not changed. APP (vlan07) has NFS and SSH to the NAS and a pass to everything except PrivateNetworks, so the whole VLAN reaches the internet, not one application. The separate WAN audit (WireGuard and Grocery only) is opnsense-wan-audit and waits until the end."
    status: pending
  - id: weekly-security-audit
    content: "Package 2 (operator 2026-10-20): a weekly audit on a timer — nmap S7 from IOT, Trivy of images, versions, OPNsense rules — report by mail and on the NAS, never in public-repo artifacts"
    status: pending
  - id: ubuntu-2604
    content: "After release PR #78 (operator 2026-10-21): move the apps and NAS VMs from Ubuntu 24.04 to 26.04 — DEV first, with a rebuild and restore drill, then prod as its own release. Changing the image (terraform/environments/*/terraform.tfvars image_url) is likely a VM replacement (risk gate). It does not fix rclone: 26.04 still ships 1.60.1 in apt, so tools stay pinned to an upstream version"
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
    content: "Last (operator 2026-10-22): audit OPNsense rules. Only WireGuard and Grocery should leave on WAN. Read the rules, compare with docs/network.md (WAN 443/tcp and 51820/udp). Do not change the configuration until the audit shows a difference and the operator accepts it."
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
