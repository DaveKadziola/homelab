---
name: Homelab greenfield dummy
overview: Greenfield homelab v2 — iteration.
todos:
  - id: secrets-gh
    content: "F0-10 done: docs/secrets-inventory.md + manual-setup + apps-sources (4d0ab71)"
    status: completed
  - id: secrets-vault
    content: "A10 done: Bitwarden PM + 2FA + folder homelab + TF_API_TOKEN/prod (user 2026-06-11)"
    status: completed
  - id: hardware
    content: "A5 as-built done 2026-06-30; PVE and T620 MACs are on the router (docs/network.md:43,45), prod built 2026-10-20 (VM 101/102, CT 110)"
    status: completed
  - id: apps-decisions
    content: "Closed in iteration #2: P0/P1/P2, Trilium, Actual, Navidrome, Syncthing P1, Jellyfin P1, Zotify deferred"
    status: completed
  - id: apps-inventory
    content: "Application table — P0/P1/P2 phases done this iteration."
    status: completed
  - id: apps-repo-verify
    content: "Gate A16: check the GitHub source of every app; docs/apps-sources.md; checkboxes in the plan"
    status: completed
  - id: backup-dr
    content: "A15 sizing done; A9 partial (pCloud 500GB account exists, no rclone OAuth — storage work); retention done"
    status: completed
  - id: security
    content: "B3/B4/B14 done; Grocery public: grocery.dkhomelabserver.xyz (A6 done 2026-06-11)"
    status: completed
  - id: phases
    content: "P0/P1/P2 done this iteration."
    status: completed
  - id: gha-cleanup-secrets
    content: "F0/A0: legacy GitHub secrets and variables removed (2026-06-11)"
    status: completed
  - id: gha-pipelines
    content: "F1: GitHub Actions, two runners; homelab-v2 is DEV, main is prod; v2 workflows (ci-validate, deploy-dev, …) implemented. CI was down from 2026-07-01 (no runner) until R1. Done 2026-10-18: CI Validate, Infra Plan/Apply Dev, Apps Deploy Dev and Tests Dev run on the homelab-dev runner"
    status: completed
  - id: gha-runner-bootstrap
    content: "F1 done: DEV runner on the laptop (systemd); prod runner is LXC CT 110 ci-runner on the PVE host (utils/pve-ci-runner-lxc.sh, #60/#63), laptop runner unregistered"
    status: completed
  - id: branch-v2
    content: "F0-09/10 done: homelab-v2 + docs commit 4d0ab71"
    status: completed
  - id: manual-setup-f0
    content: "Sprint F0 done: F0-01 through F0-12 complete (gate 2026-06-11); docs English cdc77f7"
    status: completed
  - id: readme-docs
    content: "README.md documents what this is, how it is built and where to start — README + knowledge/ (audit 2026-10-18)"
    status: completed
  - id: preflight
    content: "Gate F0 to F1 done 2026-06-11; A9 rclone OAuth moved to storage work; A5 MAC moved to the Proxmox host work"
    status: completed
  - id: implement
    content: "F1 done: CI. Router scripts done (#26-#33, #55). Prod built from main (#75)"
    status: completed
  - id: identities
    content: "Iteration #3: config/identities.yml + credential generator (admin/prod/dev/notification) — done e28840f, 5f37cd4; config suite PASS 2026-10-18"
    status: completed
  - id: config-as-code
    content: "Iteration #3 done: matrix + bootstrap/ (9f8afe2); prod Apps Deploy Prod 39462592254 — bootstrap table Failed: 0"
    status: completed
  - id: tests-auto
    content: "Iteration #3 done: tests/ (smoke, infra, net, config, storage, ha, restore); prod 151/0/11 (39462592254), dev 147/0/16 (39460389233)"
    status: completed
  - id: knowledge-base
    content: "Iteration #3: docs/kb/ + lessons-learned (append-only, entries from the DEV bring-up) — done 151d4e4; since 2026-10-18 in knowledge/"
    status: completed
  - id: rebuild-runbook
    content: "Iteration #3 done: knowledge/rebuild.md + drill on nested DEV (knowledge/rebuild-drill-2026-10-19b.md: pass with no code change)"
    status: completed
  - id: audit-final
    content: "Prod audit 2026-10-20 (knowledge/security-audit-2026-10-20.md): S7 from LAN/IOT/APP done; left: scan from WireGuard and WAN, fixes S16-S27 (each one needs consent)"
    status: in_progress
  - id: restore-ci
    content: "Iteration #4 R1: register the homelab-dev runner again as a service; CI Validate + Infra Plan Dev green, Tests Dev starts — done 2026-10-18: runner is a systemd service; CI Validate and Infra Plan Dev green; Tests Dev runs (#9-#13)"
    status: completed
  - id: restore-dev
    content: "Iteration #4 R2: nested Proxmox with an IP (utils/ensure-dev-proxmox.sh) + ubuntu-apps-dev; run-tests --env dev --suite all with no FAIL — done 2026-10-18: the hangs were a full LVM-thin pool; state in HCP homelab-dev; run-tests 161 PASS / 0 FAIL"
    status: completed
  - id: f9-gate-dev
    content: "Iteration #4 R3 done: drill 10-19b with a real DEV wipe passed with no code change; restore suite passed"
    status: completed
  - id: monitoring-alerts
    content: "Done 2026-10-22: SMTP works, the operator gets mail. Diun has DIUN_NOTIF_MAIL_* in diun.env on prod. In 48 h of logs there was no new tag to send; there were registry timeouts."
    status: completed
  - id: ai-log-analysis
    content: "Package 2 (operator 2026-10-20): AI summaries through OpenRouter of cleaned audit results and logs (allowlist, aggregation); nothing raw into the public repo"
    status: pending
  - id: project-cleanup
    content: "Done 2026-10-22: worktree homelab-grocery-prod removed. feat/grocery-v2-prod and fix/grocery-no-debug deleted from origin (the Grocery fix is already 6c13608 on homelab-v2; the grocery rewrite sentence is in docs/network.md). Local branches of merged PRs deleted. ansible/docker-containers.yml, utils/create-dev-vm.sh and ansible/user-setup.yml have been gone since 07bb30e. origin/dev stays: 26 commits are not in tag legacy-pre-v2. docs/opnsense-ui-walkthrough.md stays because the baseline and opnsense-verify.sh point at it."
    status: completed
  - id: docs-readme
    content: "Done 2026-10-22: README.md already says what this is, how it is built and where to start. It was not rewritten."
    status: completed
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
  - id: ci-autonomy
    content: "Done 2026-10-22: the reviewer left the prod environment. Infra Apply asks once (prod-approve). A risky plan or gate=true stops on prod-gate. A successful apply starts Apps Deploy with no second click (run 39806560198, job approve skipped). A manual app deploy still asks once."
    status: completed
  - id: homarr-links
    content: "Done 2026-10-22: tiles use names, the seed comes from deploy. The operator opened prod Homarr (Beszel widget), so the admin account in the UI exists."
    status: completed
  - id: ha-as-code
    content: "Done 2026-10-22: HA_TOKEN is in the prod environment, deploy runs utils/ha.py, prod ha tests 5 PASS / 0 FAIL."
    status: completed
  - id: app-names-proxy
    content: "Done 2026-10-22: CLOUDFLARE_API_TOKEN is in the prod environment, AdGuard rewrites have been in place since 2026-10-21, the HTTPS names answer."
    status: completed
  - id: backups-nas-pve
    content: "Done 2026-10-22: the OPNsense key is on the router (forced command), in GitHub env prod, in Bitwarden and on the NAS. First dump: /srv/purple/nas-backups/opnsense/config-20261022T131513Z.xml (mode 600). The prod HA_TOKEN was already there."
    status: completed
  - id: weekly-security-audit
    content: "Package 2 (operator 2026-10-20): a weekly audit on a timer — nmap S7 from IOT, Trivy of images, versions, OPNsense rules — report by mail and on the NAS, never in public-repo artifacts"
    status: pending
  - id: nic-error-metrics
    content: "Done 2026-10-22: cron on PVE daily at 06:15. Growth is mailed over SSH to the apps host (forced command, the SMTP secret stays on 192.168.50.30). Existing counters do not alert, only growth. Revert: rm /etc/cron.d/homelab-nic-errors /usr/local/sbin/nic-errors.sh /var/lib/homelab/nic-errors.prev /root/.ssh/homelab-nic-mail /root/.ssh/homelab-nic-mail.pub and the homelab-nic-mail line in ubuntu-prod authorized_keys."
    status: completed
  - id: ubuntu-2604
    content: "After release PR #78 (operator 2026-10-21): move the apps and NAS VMs from Ubuntu 24.04 to 26.04 — DEV first, with a rebuild and restore drill, then prod as its own release. Changing the image (terraform/environments/*/terraform.tfvars image_url) is likely a VM replacement (risk gate). It does not fix rclone: 26.04 still ships 1.60.1 in apt, so tools stay pinned to an upstream version"
    status: pending
  - id: nfs-root-squash
    content: "Stays no_root_squash. Read 2026-10-22: /export for 192.168.50.0/26 and vzdump for 192.168.20.20. Jellyfin on prod runs as root and owns /media. root_squash would remove its write. The export was not changed."
    status: completed
  - id: authelia-ip-bypass
    content: "Closed 2026-10-22 (operator): apps with their own login have auth_bypass all. Ports stay off 127.0.0.1. Kuma on the T620 checks them with TCP; closing the IP would mail that a live app is down."
    status: completed
  - id: homarr-ha-domain
    content: "Done 2026-10-22: the prod Home Assistant tile is http://hass.dkhomelabserver.xyz/ (board on the host, ping off)."
    status: completed
  - id: pr78-merge-checklist
    content: "Closed 2026-10-22: the #78 checklist is fully checked. The gate item was checked after Apps Deploy 39806560198 ran with job approve skipped. Zotify volumes and BESZEL_KEY are gone."
    status: completed
  - id: deploy-prod-timeout
    content: "Done 2026-10-22: the deploy-prod job has timeout-minutes 120. Apps Deploy Prod 39746487452 finished deploy-prod in 21m45s, under the limit."
    status: completed
  - id: ansible-python-interpreter
    content: "Done 2026-10-22: ansible_python_interpreter=/usr/bin/python3 in the prod and dev inventories. The same Apps Deploy Prod ran Ansible with no discovery warning."
    status: completed
  - id: homarr-network-tiles
    content: "Done 2026-10-22: prod has Proxmox :8006, AdGuard https://adguard.dkhomelabserver.xyz:8443/, OPNsense https://router.dkhomelabserver.xyz/, the switch and the access point. Deploy 39755554518. The switch on port 80 did not answer from the laptop."
    status: completed
  - id: diun-updates
    content: "Done 2026-10-22: Diun mails new container tags. Timer homelab-host-updates (Sunday 06:15) mails apt packages and a newer Ubuntu image serial when /etc/cloud/build.info differs from cloud-images.ubuntu.com. On prod apps and the NAS the serial is 20261017, the same as published. A newer serial means rebuilding the VM, not apt."
    status: completed
  - id: diun-homarr-access
    content: "Done 2026-10-22: Diun 4.33.0 has no GUI (knowledge/apps/diun.md). There is no dead tile. The way in is a Dozzle log or the mailbox. Diun sent no mail for 48 h."
    status: completed
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

The backlog is the frontmatter of this file. The June and July notes are in
[`greenfield-notes.md`](greenfield-notes.md) and are not a procedure.
