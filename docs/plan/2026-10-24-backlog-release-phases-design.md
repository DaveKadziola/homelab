# Backlog release phases - design

Status: draft for operator review
Date: 2026-10-24
Source of the backlog: frontmatter of [`greenfield-plan.md`](greenfield-plan.md) on `develop`
(commit 153a813).

## 1. Goal and constraints

Work through the open backlog from the least to the most invasive item with as few prod
releases (`develop` -> `main` PRs) as possible, each release as large as is safe.

Agreed with the operator on 2026-10-24:

- Scope is invasiveness levels 1-3 (section 2). Level 4 (rebuilds) stays in the backlog for its
  own design.
- When a read-only audit finds something to change, the fix becomes its own backlog item and is
  implemented in this plan (R1 if it only adds, R2 if it changes something that exists).
- Docker image updates are in scope (Diun reported newer tags).
- Two releases (approach 1 of three considered; one big release and three releases rejected).
- Manual changes on prod hosts (Proxmox, Home Assistant, router) count as prod deployments and
  are done in the window of a release, not on their own.
- Read-only prod work runs through a Remote Control session on the operator's laptop: the cloud
  workspace has no route to the home network.
- Every phase has reviewer and critic agents whose job is to find what passes on DEV and fails
  on prod (section 6).
- No phase may lose data, configuration, a database or a credential irreversibly
  (section 5).

Unchanged rules from `PROJECT-CONTEXT.md` section 3: the operator merges every release PR and
approves `prod-approve` / `prod-gate`; no direct push to `develop` or `main`; the router's live
configuration is changed only by the operator; a plan that replaces `ubuntu-apps` stops the
release.

## 2. Invasiveness levels

| Level | Meaning | Items |
| --- | --- | --- |
| 1 | Read-only on prod; work on DEV and in the repo only | monitoring-audit, adguard-review, opnsense-wan-audit, syncthing-smb-check, backup-decrypt-drill, rebuild-data-safety, ai-cost (measuring), container-file-access (check Portainer), joplin-to-trilium (DEV test and docs), trilium-ai-access (research), image inventory |
| 2 | Adds to prod; nothing existing changes meaning | weekly-security-audit, ai-log-analysis, monitoring gap fixes, patch/minor image updates, file browser, db-admin-tool (CloudBeaver next to pgAdmin), homarr-dashboard-widgets, postgres-unused-dbs (list cleanup only) |
| 3 | Changes or removes something on prod | pve-hardening, admin-certs, postgres-unused-dbs (DROP on prod), pgAdmin removal, public-map-split, image updates with a data migration, audit fixes that change config; then git-history-state |
| 4 | Rebuilds - out of scope | ubuntu-2604, disk-encryption, subnet-refactor, home-assistant-zigbee |

`security-audit-fixes` and `security-public-repo` are umbrella items: they close when
pve-hardening, admin-certs, public-map-split and git-history-state close.

Removing a name from `databases:` in `config/services.yml:59` deletes nothing on prod: compose
only creates missing databases (`compose/core/docker-compose.yml:47`). That is why the list
cleanup is level 2 and the DROP is level 3.

## 3. Phases

### Phase 0 - read-only, no deploy

One Remote Control session on the laptop. Reads on prod run one after another, never in
parallel (`AGENTS.md` section 6). Order:

1. Image inventory: current tag in `compose/` vs the newest stable tag, bump type, migration
   notes. A first unverified web lookup (2026-10-24) found patch updates for Syncthing, Portainer,
   Immich, Dozzle, Postgres 16 and Valkey 8, minor for Jellyfin and Homarr, an unclear state for
   Beszel and caddy-dns/cloudflare, and PostgreSQL 14 in the Immich database image reaching end of
   life on 2026-11-12. Phase 0 checks each against the registry and upstream notes.
2. backup-decrypt-drill: rclone config from Bitwarden on a clean machine, list `pcloud-crypt`,
   copy one dump, restore it on DEV with `utils/backup/restore-pg.sh`; pCloud size and age of
   `.offsite-ok` on prod.
3. rebuild-data-safety: list what no backup holds (Samba `share`, `media/sync`, media
   libraries) and what a prod rebuild needs by hand; volume-tar restore on DEV, which the
   2026-10-19 drills did not exercise (`knowledge/rebuild-drill-2026-10-19.md:46`).
4. monitoring-audit: failure list against Uptime Kuma, Beszel, Diun, Trivy, apt and NIC mails,
   backup freshness.
5. syncthing-smb-check, adguard-review, opnsense-wan-audit (the scan from outside is done by
   the operator from a phone hotspot), ai-cost measurement.
6. Repo and DEV only: Portainer file access check, Joplin -> Trilium export test on DEV,
   trilium-ai-access research.

Output: findings in `knowledge/` (one document per audit), each finding that needs a change
as a new backlog item tagged R1 or R2. Phase 0 ends with an operator review of that list; a
finding that needs level 4 work goes to the backlog, not into R1 or R2.

### Release 1 - additions

One PR per item into `develop`, in this order:

1. Patch image updates.
2. `databases:` list cleanup.
3. Monitoring gap fixes from Phase 0 (known: update reports for OPNsense and Home Assistant).
4. weekly-security-audit.
5. ai-log-analysis (uses the weekly audit output and the ai-cost result).
6. Minor image updates, CloudBeaver next to pgAdmin, file browser (read-only by default),
   Homarr widgets if the new Homarr version supports them.
7. Phase 0 fixes tagged R1.

Items without a design (weekly-security-audit, ai-log-analysis, container-file-access) get a
short brainstorming of their own before implementation. Then one release PR.

After R1 the operator can import Joplin notes into prod Trilium by hand (it only adds data).

### Release 2 - changes to existing prod

One PR per item into `develop`, in this order:

1. public-map-split (own brainstorming first; it changes where the deploy reads addresses).
2. admin-certs.
3. pve-hardening: the Terraform provider change (SSH key, new `privsep=1` token) together with
   the host changes in the release window.
4. DROP of the unused databases and pgAdmin removal.
5. Image updates with a data migration (Immich Postgres 14) - only with an upstream migration
   path; without one the item moves back to the backlog.
6. Phase 0 fixes tagged R2.

trilium-ai-access gets its own brainstorming after Phase 0; it is placed in R1 or R2 by what the
design changes.

### After R2 - history rewrite, no deploy

git-history-state: one rewrite, force-push of `main` and `develop`. Asked separately, because it
cannot be undone and every clone and runner checkout becomes stale.

## 4. Release mechanics

Every item reaches `develop` through a PR that merges itself after `validate` and `plan`
(`PROJECT-CONTEXT.md` section 5). DEV deploys and runs the post-deploy tests. The release PR is
opened only when the gate in section 5 passes and the parity review in section 6 has no open
finding.

## 5. Data safety

Before every release:

1. Run `homelab-backup` on apps and `homelab-nas-backup` on the NAS by hand; check
   `check-fresh.py` and the age of `.offsite-ok`.
2. Restore those dumps and volume tars on DEV and run `utils/run-tests.sh --env dev --suite all`.
   The release PR waits for this result.
3. Infra Plan Prod must show no VM replace or destroy. A plan that `utils/tf-plan-risk.py`
   sends to `prod-gate` stops the release until the operator decides.
4. Rollback of an image update is a revert of its PR. That only holds when the update has no
   schema migration, which is why migrating updates are in R2 with their own dump.

Release 2, per item:

- DROP DATABASE only after a dump that restores on DEV; the dump stays on the NAS. Each DROP is
  confirmed by the operator.
- pve-hardening with the console at hand: TFA and the SSH key first, a login test from a second
  session, only then `PasswordAuthentication no` and the PVE firewall. The old token is deleted
  after a real apply with the new one.
- Immich Postgres: dump, restore and app test on DEV before prod.

After every release, `knowledge/` records the changes that outlive the session with the
command that reverses each one (`AGENTS.md` section 11).

## 6. Reviewers and critics

Each phase has three review roles, run by separate agents that did not write the change:

| Role | When | Looks for |
| --- | --- | --- |
| PR reviewer (`agents/reviewer.md`) | every PR into `develop` | correctness, conventions, tests, secrets |
| Parity critic | every PR, and the release PR as a whole | anything that behaves differently on prod than on DEV (list below) |
| Release critic | before the release PR is opened | the combined diff `main..develop`, the data-safety gate evidence, the rollback of each item, what the DEV tests did not cover |

The parity critic checks each change against the known differences between the environments:

- Proxmox: nested PVE in libvirt on DEV, metal on prod; Terraform user `root@pam` on DEV,
  `homelab-prod@pam` on prod.
- Network: libvirt NAT on DEV; VLANs with the OPNsense router filtering every packet to APP on
  prod. Recent prod-only fixes came from this (`ef2c132` STUN egress, `c722876` NFS behind the
  NAS firewall).
- NAS: loopback NFS on the same guest on DEV, a separate VM with its own firewall on prod
  (`2e64c9c`, `18fba58`, `ec33703` were prod-only).
- Streams that skip on DEV: OPNsense config backup, rclone offsite (`knowledge/backup.md:17,20`).
- Home Assistant: HAOS twin on DEV, T620 on prod.
- Runner: laptop runner on DEV, LXC `ci-runner` on the prod Proxmox host.
- Proxy: HAProxy and ACME on the router exist only on prod.
- Secrets and environment values: GitHub environment `dev` vs `prod`.

A change that touches one of these needs either a test that runs on prod after deploy
(post-deploy tests) or an explicit manual check in the release checklist. A finding the critic
cannot settle on DEV is listed in the release PR as a prod check.

## 7. Delegation and models

| Work | Model tier |
| --- | --- |
| Version and release-note lookups, doc checks | small (Haiku) |
| Well-described R1 PRs (compose, timers, docs), each with a filled task card | medium (Sonnet) |
| Phase 0 analysis, all of R2, data decisions, release critic | large (Opus) |
| PR reviewer and parity critic | medium for R1, large for R2 |

One model per item from start to merge (`AGENTS.md` section 13).

## 8. Out of scope

Level 4 items; changes to the router's live configuration by the agent; retiring
`utils/bootstrap-secrets.sh` (open question in `PROJECT-CONTEXT.md` section 8).
