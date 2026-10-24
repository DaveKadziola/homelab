---
name: Homelab greenfield dummy
overview: Greenfield homelab v2 — iteration.
todos:
  - id: security-audit-fixes
    content: "Prod audit 2026-10-20 (knowledge/security-audit-2026-10-20.md); replaces audit-final and security-audit-hosts. Closed 2026-10-23: S4 (Caddy terminates TLS, Authelia is plain HTTP behind it), S5, S9 (the 15 laptop copies shredded; the NAS keeps opnsense/config-*.xml daily), S11 (curl: Actual bootstrapped true, Trilium isInitialized true), S21 (OPNsense 26.7.7, pkg audit -q lists nothing), S26 (the noble-security packages came through unattended-upgrades; the noble-updates ones applied by hand, containerd restarted, no container restarted). Accepted: S12 (key only), S22 (nfs-root-squash). Agreed fixes, one item each: admins-alias, host-firewalls, pve-hardening, runner-key-cleanup, sshd-x11, trivy-daily, admin-certs. S7 from WireGuard and WAN goes with opnsense-wan-audit. Closed 2026-10-24 by the router window (admins-alias): S16, S17, S24 on the router (53530, AdGuard UI) and S25; S1 and S2 from LAN and WireGuard for non-Admins (the host firewalls stay open in host-firewalls). Closed 2026-10-24 with v2.4.0 (checked on prod): S6 on the NAS (host-firewalls; apps is filtered by the router, Proxmox goes with pve-hardening), S24 on the NAS (mountd and statd closed, rpcbind only from Proxmox), S15 (trivy-daily), S20 (runner-key-cleanup), S27 on the NAS and apps (sshd-x11). Left: pve-hardening, admin-certs."
    status: in_progress
  - id: pve-hardening
    content: "Operator 2026-10-23: TFA for root@pam; Terraform SSH by key, then PasswordAuthentication no (S18); PVE firewall with 22/8006 from Admins and the runner, overriding the default management set (S18, S24); X11Forwarding no (S27). Token: a role with the privileges the bpg provider needs, a new privsep=1 token tested on DEV, swap the secret, delete the old token after a real apply (S19). Console at hand."
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
  - id: monitoring-audit
    content: "Operator 2026-10-23: audit the alerts and monitors for gaps. List what can fail (each service, host, VM, disk, NFS mount, backup stream, certificate, router, runner, CI and prod deploy) against what Uptime Kuma, Beszel, Diun, Trivy, the apt and NIC mails and the backup freshness check watch and mail (knowledge/monitoring.md, config/monitoring.yml); name what nobody would notice. Known and accepted: a dead T620, router or uplink sends nothing (decision 0006). Known gaps to cover (operator 2026-10-23): Beszel shows pending updates only for the native Linux agents (prod-nas, prod-pve); prod-apps (container agent) has the weekly apt mail, but nothing reports updates of OPNsense (FreeBSD pkg, firmware) or Home Assistant (core, OS, add-ons; its agent is an add-on). Read-only; each fix is its own item and needs consent."
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
  - id: container-file-access
    content: "Operator 2026-10-24: browse container files from the laptop and a script that maps the drives there. Today: Dozzle for logs, Portainer and docker exec / docker cp over SSH for the rest; NAS data through the Samba shares share, media, photos, backups (ansible/playbooks/deploy-storage.yml:514-570). Docker volumes on the apps VM disk have no share. Check what Portainer already gives before adding a file browser or SFTP; read-only by default."
    status: pending
  - id: rebuild-data-safety
    content: "Operator 2026-10-24: prove that a change that rebuilds a VM or recreates containers loses no data, config, database or credential, and that everything comes back from backups. A replace of ubuntu-apps wipes the Docker volumes (knowledge/deployment.md:55); the wipe drill passed on DEV 2026-10-19 (knowledge/rebuild-drill-2026-10-19b.md). List what no backup holds (the Samba share, media/sync, the media libraries) and what a prod rebuild needs by hand. DEV first."
    status: pending
  - id: postgres-unused-dbs
    content: "Operator 2026-10-24: config/services.yml:59 creates homelab, linkwarden, firefly3, actual, trilium, grafana, easytodo, vsum. Users found: linkwarden (compose/core/docker-compose.yml:134), vsum (its depends_on), grocery (easytodo); no firefly3 or grafana service exists, Trilium and Actual keep their own files. Move an app to Postgres where upstream supports it; drop the rest from the list and, after a dump, from prod (asked each time)."
    status: pending
  - id: db-admin-tool
    content: "Operator 2026-10-24, after postgres-unused-dbs: if apps stay on SQLite, consider CloudBeaver instead of pgAdmin, since it opens other engines too. Check how it reaches SQLite files inside other containers' volumes and that a running app's file is opened read-only."
    status: pending
  - id: joplin-to-trilium
    content: "Operator 2026-10-24: a manual Joplin -> Trilium migration. Test the export/import formats on DEV, then write the steps in knowledge/apps/trilium.md."
    status: pending
  - id: trilium-ai-access
    content: "Operator 2026-10-24: AI may read only the Trilium notes and knowledge base the operator allows; private notes never leave the home network. vsum already writes to Trilium with VSUM_TRILIUM_TOKEN (knowledge/apps/vsum.md:50). Open: whether a token can be limited to a subtree, and a local model vs OpenRouter."
    status: pending
  - id: ai-cost
    content: "Operator 2026-10-24: keep AI costs low (coding agents, OpenRouter for vsum and ai-log-analysis). Measure the spend first, then credit limits per key, cheaper models for routine work, fewer tokens per task."
    status: pending
  - id: syncthing-smb-check
    content: "Operator 2026-10-24: check that a file synced from the phone shows up on the laptop. Syncthing writes HomelabSync to media/sync on the SA500 (config/storage.yml:107, knowledge/apps/syncthing.md); the laptop sees it in the Samba share media, folder sync, not in share (deploy-storage.yml:521-526). Check on prod: the phone paired, the folder under HomelabSync, a test file visible over Samba, file ownership between the container and the Samba force user. media/sync has no backup."
    status: pending
  - id: backup-decrypt-drill
    content: "Operator 2026-10-24: what is encrypted and how to read it back. On pCloud: postgres, volumes, homeassistant, repo-zip (config/storage.yml:126-129) through the rclone crypt remote pcloud-crypt, whose passwords are only in RCLONE_CONFIG (GH env prod, Bitwarden homelab/RCLONE_CONFIG/prod). On the NAS the dumps and tars are plain, the HA tars use HA_BACKUP_PASSWORD, VM dumps and router config sit unencrypted in NAS-private. Write and test the read-back from a clean machine (rclone config from Bitwarden, list, copy one dump, restore-pg on DEV); check the pCloud size and the age of .offsite-ok on prod."
    status: pending
  - id: disk-encryption
    content: "Operator 2026-10-24: protect the data if the server is stolen, without a daily step. B14 chose no LUKS at the start and left LUKS with clevis/TPM for later (docs/plan/greenfield-notes.md:294,561). Compare TPM unlock with network unlock (Tang on another device) for the case where the whole box is taken. Data disks need a reformat: backups and a restore test first."
    status: pending
  - id: adguard-review
    content: "Operator 2026-10-24: analyse AdGuard Home traffic (query log, top clients and domains, blocked share) and review the active filter lists; propose changes. AdGuard runs on the router: read only until the operator accepts a change."
    status: pending
  - id: public-map-split
    content: "Operator 2026-10-22: the public repo stays a portfolio (architecture, how deploy works). The house map (addresses, domain, mail) moves to gitignored docs and/or a module from a private repo. Current files have to be rewritten with example addresses. Do not touch history yet: one rewrite is git-history-state, after this swap, not before."
    status: pending
  - id: git-history-state
    content: "After public-map-split (operator 2026-10-22): remove terraform/terraform.tfstate and terraform/terraform.tfstate.backup from the whole history (added in 18dd8c6, removed in ce25d3a; six 192.168 addresses, no passwords) and the old house map. One history rewrite, force-push main and develop. git-filter-repo is not installed. After that every clone is stale; GitHub can keep old objects until it purges them. Do not do this before the files are swapped, or the map comes back in new commits."
    status: pending
  - id: opnsense-wan-audit
    content: "Last (operator 2026-10-22): audit OPNsense rules. Only WireGuard and Grocery should leave on WAN. Read the rules, compare with docs/network.md (WAN 443/tcp and 51820/udp). Do not change the configuration until the audit shows a difference and the operator accepts it. Includes S7 from WireGuard and WAN (a scan from outside, e.g. a phone hotspot)."
    status: pending
  - id: subnet-refactor
    content: "At the very end, after opnsense-wan-audit (operator 2026-10-22): subnet refactor. The operator thinks the VLAN layout can be better. There is no design yet. Change nothing until a layout is approved. Decide with the layout whether ubuntu-apps needs its own host firewall (DOCKER-USER): on 2026-10-24 it is alone in the APP VLAN, so the router filters every packet to it (operator 2026-10-24: not before then)."
    status: pending
  - id: home-assistant-zigbee
    content: "Operator 2026-10-24, after the homelab items above: Home Assistant (HAOS on the T620) with the Tuya devices through a Zigbee gateway, controlled from outside home. Open: the gateway (Tuya hub through the Tuya cloud vs a local Zigbee coordinator) and the remote path (the existing WireGuard vs a public URL)."
    status: pending
isProject: false
---

# Homelab plan

Open work (pending and in progress) is the frontmatter of this file. Move an item to
[`greenfield-completed.md`](greenfield-completed.md) when it is done. The June and July notes are in
[`greenfield-notes.md`](greenfield-notes.md) and are not a procedure.
