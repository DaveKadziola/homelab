# Homelab knowledge base

This directory is the operator entry. The repo README only links here. It is also the knowledge
base the agent rules in `AGENTS.md` (section 12) refer to: what an agent reads instead of guessing,
so a wrong entry costs more than a missing one.

| Page | What |
|------|------|
| [architecture.md](architecture.md) | Envs, source of truth, what is / is not built |
| [infrastructure.md](infrastructure.md) | Proxmox, TF, runners, VM sizing |
| [networking.md](networking.md) | Dev vs prod, app names behind Caddy + Authelia, exposure |
| [prod-target.md](prod-target.md) | What the prod rollout creates, from which file; gaps found and fixed |
| [storage.md](storage.md) | DEV volumes + loopback NFS; prod SA500 (media) / Purple (backups + share), attach order, one-time wipe; Samba; why Ubuntu not OMV/TrueNAS |
| [backup.md](backup.md) | F5 jobs on the apps host, the NAS and Proxmox; timers; restore suite |
| [monitoring.md](monitoring.md) | Uptime Kuma on Home Assistant, backup freshness pushes, Beszel, Diun, alert mail per env |
| [dr.md](dr.md) | What you can and cannot recover today |
| [security.md](security.md) | Identities, rotation, known edges |
| [deployment.md](deployment.md) | Ansible, bootstrap order, grocery |
| [operations.md](operations.md) | Login table, add-an-app, tests |
| [troubleshooting.md](troubleshooting.md) | Symptom → check |
| [rebuild.md](rebuild.md) | Clean-room order |
| [lessons-learned.md](lessons-learned.md) | Append-only post-mortems |
| [apps/](apps/) | One page per service |
| [security-audit-2026-09-10.md](security-audit-2026-09-10.md) | F9-F1 — DEV nmap / inspect / gitleaks |
| [security-audit-2026-10-20.md](security-audit-2026-10-20.md) | F9-F1 on prod - S7 nmap from LAN/IOT/APP, host review, findings S16-S27 (IOT reaches router admin, password SSH on router and PVE, uninitialised Actual/Trilium) |
| [repo-audit-2026-09-10.md](repo-audit-2026-09-10.md) | F9-F2 — stranger readability |
| [rebuild-drill-2026-09-10.md](rebuild-drill-2026-09-10.md) | F9-F3 — tabletop; merge gate FAIL at the time, met since by the 2026-10-19b drill; prod built from `main` by release #75 |
| [rebuild-drill-2026-10-19.md](rebuild-drill-2026-10-19.md) | F9-F3 — real wipe + rebuild of DEV; works, 9 gaps found; repeated in 2026-10-19b |
| [rebuild-drill-2026-10-19b.md](rebuild-drill-2026-10-19b.md) | F9-F3 — repeat wipe + rebuild of DEV; pass with no code change, about 30 minutes |
| [decisions/](decisions/) | Decision records (ADR); 0001 - restore CI and DEV before F3 metal; [0002](decisions/0002-nas-layout-and-samba.md) - NAS layout by data type, Samba on the Ubuntu NAS; [0003](decisions/0003-prod-without-authelia.md) - prod without Authelia until a proxy (superseded by 0007); [0004](decisions/0004-ci-autonomy-and-prod-risk-gate.md) - auto-merge into homelab-v2, one approval on Infra Apply Prod, Apps Deploy follows it with no second click, prod-gate when the plan is risky; [0005](decisions/0005-home-assistant-as-code.md) - HA packages from the repo, HAOS twin on DEV, UI files snapshotted; [0006](decisions/0006-alerts-kuma-proton-smtp.md) - alerts from Uptime Kuma on the T620, mail through Proton SMTP; [0007](decisions/0007-app-names-caddy-authelia.md) - app names through Caddy with Authelia, supersedes 0003; [0008](decisions/0008-keep-kuma-diun-and-beszel.md) - Kuma stays the uptime mailer, Diun the image-tag mailer, Beszel the host metrics; [0009](decisions/0009-release-tag-after-prod-deploy.md) - tag and release after a green prod deploy, bullet-point notes |
| [templates/](templates/) | Templates for new decision, how-to, runbook, troubleshooting and glossary documents |

## What goes in, what does not

| Goes in | Stays out |
| --- | --- |
| Facts confirmed by the operator or by a run | Guesses, one-off observations, "probably" |
| Decisions and their reasons | Status of a single task or a branch |
| Procedures that were actually executed | Procedures nobody has run |
| Known symptoms with cause and fix | Secrets, tokens, passwords, personal data |
| Project terms | Machine-local paths and personal aliases |

Private tool memory is not a substitute: it is invisible to other tools, other machines and other
people. If a fact would still be true on another machine, it belongs here.

## Document kinds in this directory

| Kind | Where | Notes |
| --- | --- | --- |
| Topic page | `<topic>.md` (flat) | One subject each, listed in the table above |
| App page | `apps/<app>.md` | One page per service in `config/services.yml` |
| Dated report | `<name>-YYYY-MM-DD.md` | Audits and drills; a snapshot, not edited afterwards except to mark it superseded |
| Lessons learned | `lessons-learned.md` | Append-only; earlier rows are never rewritten |
| Decision (ADR) | `decisions/NNNN-short-title.md` | From `templates/decision.md`; numbered, never renumbered |
| How-to | `howto/<verb>-<object>.md` | From `templates/howto.md` |
| Runbook | `rebuild.md`, or `runbooks/<service>-<operation>.md` | From `templates/runbook.md` |
| Troubleshooting | `troubleshooting.md` | Entries shaped like `templates/troubleshooting.md` |

Lower-case file names, words separated by `-`.

## Header for new documents

A document created from now on starts with:

```
Status: draft | verified | superseded by <file>
Last reviewed: YYYY-MM-DD
Scope: <what this covers, one line>
```

Existing pages do not have it yet; add it when a page is next edited.

## Marking certainty

- A statement without a marker is verified.
- An unverified statement is marked inline: `(unverified: <why it is still open>)`.
- A diagnosis can be verified while the fix is not: write them as separate statements and mark
  the fix `(unverified: no confirming run yet)` until a run confirms it.

## Citing sources

Each verified fact names what verified it, at the end of the entry or in a `Sources` section:

- code: `path/to/file:line` (and the commit if the line may move);
- a run: the command, the date and the relevant output line;
- a person: "confirmed by the operator, YYYY-MM-DD".

Never paste secrets or full logs; quote the one line that matters.

## Changing the knowledge base

1. Find the most specific existing document. Create a new one only when none fits, and add it to
   the table above.
2. Make the smallest edit. Do not reformat or reorder surrounding content.
3. One topic per commit, message saying what was verified and how.
4. When a document turns out to be wrong, correct it in the same task and say so in the report.
5. A superseded document is marked `Status: superseded by <file>`, not deleted.
