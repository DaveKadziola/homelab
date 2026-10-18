# Plan audit - 2026-10-18

Status: draft
Scope: `docs/plan/greenfield-plan.md` (todos and phases F0-F10) against branch `homelab-v2` at
`02ad105`, CI history on GitHub and the DEV environment as it ran on 2026-10-18. Takeover phase 4;
nothing was fixed.

## Summary

- The code is far ahead of the plan's todo list: 11 todos marked `pending` are implemented in
  commits (F1 pipelines, F7 identities/bootstrap/tests, F8 knowledge base, F9 audits).
- But almost none of it is proven to work **today**. CI has not run since 2026-07-01: the
  self-hosted runner `homelab-dev-laptop` is configured on the laptop but not running, and GitHub
  lists 0 registered runners, so every job since then waited 24 h and was cancelled. `Infra Plan
  Dev`, `Infra Apply Dev` and `Tests Dev` never succeeded at all.
- DEV is down: the libvirt VM `Proxmox` runs but has no IP address; the nested Proxmox API
  (`192.168.122.219:8006`) and `ubuntu-apps-dev` (`192.168.122.50`) do not answer. Full test run:
  config 64 PASS; smoke/infra/net FAIL or SKIP on "host unreachable".
- "Done" in this audit therefore means "implemented, evidence from September only" unless a run
  today shows otherwise.
- A 70 GB test/training VM is not possible on the laptop (27 GB free, 3.7 GiB RAM free). It is
  possible on the physical Proxmox host after F3 metal, with RAM as the limiting factor (see last
  section).

## Evidence collected today

| Check | Result |
| --- | --- |
| `utils/run-tests.sh --env dev --suite all` | config PASS=64 FAIL=0; infra 6 PASS / 6 FAIL / 2 SKIP; net 2 / 2 / 7; smoke 0 / 1 / 21; all FAILs are "host 192.168.122.50 unreachable" |
| `virsh domifaddr Proxmox` (arp and lease) | no address; VM state "running" |
| `ping` `192.168.122.219`, `192.168.122.50` | no answer |
| `gh run list --branch homelab-v2` (200 runs) | CI Validate: 8 success, last 2026-07-01; Apps Deploy Dev: 7 success, last 2026-07-01; Infra Plan Dev / Infra Apply Dev: 0 success; Tests Dev: 0 success, 4 cancelled |
| newest CI Validate run | created 2026-09-10 22:46Z, cancelled 24 h later, no runner assigned, 0 steps |
| `gh api .../actions/runners` | `total_count` 0 |
| `~/actions-runner-homelab/.runner` | agent `homelab-dev-laptop`; no runner process; `_diag` last written 2026-07-01 |
| laptop disk / RAM | `/` 710 G, 27 G free (97 %); RAM 31 GiB, 3.7 GiB available |
| prod hosts `192.168.20.20/.12/.13`, `192.168.50.30` from the laptop | no answer to ping or TCP 8006/22/8123; laptop is on `192.168.1.0/24`, so this does not show whether the hosts are off |

## Todos in the plan against the code

Status in the plan -> status found. "implemented" = code and docs exist; "verified" = a run proves
it works; "Sept" = evidence only from commit messages and docs of 2026-09-10/11.

| Todo | Plan | Found | Evidence |
| --- | --- | --- | --- |
| secrets-gh | completed | done | `4d0ab71`, `docs/secrets-inventory.md` |
| secrets-vault | completed | done (operator) | `02ad105`, `knowledge/rebuild-drill-2026-09-10.md:50` |
| hardware | in_progress | in progress - MACs and VM NICs wait for F3 | `docs/network.md:40-47` |
| apps-decisions | completed | done | `docs/apps-sources.md` |
| apps-inventory | completed | done | `docs/apps-sources.md`, `config/services.yml` |
| apps-repo-verify | completed | done | `docs/apps-sources.md:43` |
| backup-dr | completed | planning done; F5 implementation partial (see phases) | plan text; `docs/f5-storage.md` |
| security | completed | decisions done; F9 security audit has open findings | `knowledge/security-audit-2026-09-10.md` |
| phases | completed | done | plan "Fazy / sprinty" |
| gha-cleanup-secrets | completed | done (operator) | plan text |
| gha-pipelines | **pending** | implemented, **broken since 2026-07-01** (no runner); infra workflows never green | `0b4b066`, `d18426a`; CI history above |
| gha-runner-bootstrap | **pending** | implemented (`utils/setup-github-runner.sh`); dev runner registered once, **now gone**; prod runner not possible before F3 | runner checks above |
| branch-v2 | completed | done | branch `homelab-v2` |
| manual-setup-f0 | completed | done | `11daef1` |
| readme-docs | **pending** | done | `README.md`, `151d4e4` |
| preflight | completed | done | plan text |
| implement | in_progress | in progress - F1-F4, F7-F9 implemented on DEV; F3 metal, F5 prod, F6, F10 open | phases below |
| identities | **pending** | implemented; config suite PASS today | `e28840f`, `5f37cd4`, `config/identities.yml` |
| config-as-code | **pending** | implemented (Sept); not re-run today (DEV down) | `9f8afe2`, `utils/bootstrap/` |
| tests-auto | **pending** | implemented; runs locally; never ran in CI | `4c4cada`, `tests/`; `Tests Dev` 0 success |
| knowledge-base | **pending** | done | `151d4e4`, `knowledge/` |
| rebuild-runbook | **pending** | written; drill not done (rebuild from repo only is an open gate item) | `knowledge/rebuild.md`, `knowledge/rebuild-drill-2026-09-10.md:53` |
| audit-final | **pending** | audits written; gate FAIL | `29a00dd`, `70327bd`, `knowledge/rebuild-drill-2026-09-10.md:7` |
| monitoring-alerts | pending | not started (`config/monitoring.yml` absent) | tree |
| ai-log-analysis | pending | not started | tree |

## Phases

| Phase | Plan scope | Found |
| --- | --- | --- |
| F0 | plan, decisions, manual laptop setup | done (`4d0ab71`..`11daef1`) |
| F1 | GHA pipelines, GH secrets, TFC, dev VM, README skeleton | implemented; CI broken since July (runner) |
| F2 | OPNsense bootstrap, WireGuard doc, config backup | docs and scripts done (`f93ad14`, `420ad0b`, `bdab84e`, `29289f8`); router state not verifiable from here |
| F3 | Proxmox TF: NAS VM + apps VM | DEV nested done in Sept (`d18426a`, `cafdc40`, `d8e910b`); **metal not started**; DEV down today |
| F4 | Postgres + P0 apps | DEV done in Sept (`ad4b50f`..`78df749`); not reproducible today |
| F5 | HA T620, NAS backup jobs, pCloud | partial: DEV NFS/timer/restore (`35c64c0`), rclone remote (`3e102d6`); prod disks, HAOS flash, vzdump, offsite timer open |
| F6 | P1/P2 apps, Diun, Dozzle, Grafana/Beszel, README before merge | apps P1/P2 deployed on DEV in Sept (`78df749`), Beszel/Diun/Dozzle in `config/services.yml`; Grafana not present; README done - not tracked as a phase anywhere else |
| F7 | identities, apps as code, tests | implemented (`e28840f`..`9f8afe2`) |
| F8 | knowledge base, lessons learned, rebuild runbook | done (`151d4e4`) |
| F9 | audits + rebuild drill, merge gate | audits done; gate FAIL, 3 items open |
| F10 | monitoring, alerts, AI log analysis | not started (planned after prod) |

## F9 merge gate (from `knowledge/rebuild-drill-2026-09-10.md:48-55`)

| Item | State |
| --- | --- |
| Bitwarden holds the cache | done |
| F5 DEV backup + restore | partial - offsite timer DEV-disabled |
| `tests/restore/` passed on DEV | done in Sept; not re-run (DEV down) |
| Nested rebuild from repo + vault only | open |
| nmap from WG/IOT/APP | open (needs prod) |
| GHA deploy injects the full secret set, DEV test workflow runs | open - and blocked by the missing runner |

## Findings for the plan revision

1. high - CI is not running: re-register the dev runner (and decide whether it should run as a
   service) before anything else depends on CI. The plan has no item for it because it was marked
   done in July.
2. high - DEV is down (nested Proxmox without IP). Recovery comes before any further F-phase work
   on DEV; `utils/ensure-dev-proxmox.sh` is the documented entry.
3. medium - the plan's todo list is three months stale and mixes F-phases with decision tracking;
   statuses should be reconciled with the table above.
4. medium - F6 overlaps with work already done under F4/F7 (P1/P2 apps, Diun, Dozzle, Beszel);
   only Grafana and the "README before merge" item remain.
5. new requirement - a test/training VM with about 70 GB disk (below).

## Test / training VM (about 70 GB disk) - feasibility

Requirement (operator, 2026-10-18): a VM with ~70 GB disk for tests and a training course,
because the laptop has no space.

**Now, on the laptop:** not possible. 27 GB free on `/` (97 % used) and 3.7 GiB RAM available
with the nested Proxmox and another VM running.

**On the physical Proxmox host (after F3 metal):** possible, with limits.

| Resource | Host | Already planned | Left for a test VM |
| --- | --- | --- | --- |
| RAM | 16 GB (plan "PC Proxmox") | apps 8 GB + NAS 4 GB + host ~1-2 GB | ~2 GB - too little for most training VMs |
| CPU | Celeron J4205, 4 cores | 2 + 2 vCPU | shared; fine for light work |
| System SSD | 256 GB (`local-lvm`) | apps root 48 GB + NAS root 32 GB (`terraform/environments/prod/terraform.tfvars`) | General knowledge, not verified here: a default Proxmox install on 256 GB leaves roughly 140-160 GiB thin pool, so 70 GB fits but leaves little headroom |
| SA500 2 TB SSD / Purple 4 TB HDD | data disks | passed through whole to `ubuntu-nas` (`knowledge/storage.md:31-32`) | none unless the passthrough decision changes |

Options:

- **A - test VM on the system SSD**, started only when needed. 70 GB thin disk on `local-lvm`;
  RAM 4 GB by starting it on demand and lowering `ubuntu-apps` from 8 to 6 GB (the full P0-P2 stack
  ran on 6 GiB on DEV in September: `knowledge/infrastructure.md:11`, `78df749`). Fastest disk,
  tight space.
- **B - keep the Purple HDD on the host** as LVM-thin storage: the test VM and backups get space
  there, and `ubuntu-nas` receives a virtual disk on it instead of the whole drive. Plenty of
  space, slower disk; changes the F5 storage decision and `utils/pve-attach-nas-disks.sh`.
- **C - before F3:** the HP T620 (16 GB RAM, 128 GB SSD) is planned for HAOS, which is not flashed
  yet per `docs/f5-storage.md:17`. If it is idle, it could host the training VM until F5. Whether it
  is idle is unknown.

Decision (operator, 2026-10-18): the training VM goes on the laptop after freeing disk space; it
is not part of the homelab plan.
