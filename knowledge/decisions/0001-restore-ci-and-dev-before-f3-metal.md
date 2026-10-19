Status: verified
Last reviewed: 2026-10-18
Scope: order of work after the takeover - CI and DEV before F3 metal

# 0001 - Restore CI and DEV before starting F3 on metal

## Context

The plan continues with F3 on the physical Proxmox host. The takeover audit found that the base it
relies on does not work today:

- CI has not run since 2026-07-01: the self-hosted runner `homelab-dev-laptop` is not running and
  GitHub lists 0 registered runners; every job since then was cancelled after 24 h. `Infra Plan
  Dev`, `Infra Apply Dev` and `Tests Dev` never succeeded.
- DEV is unreachable: the nested Proxmox VM has no IP address; smoke, infra and net tests fail on
  "host unreachable".
- Three of six F9 gate items are open, and two of them (rebuild from repo only, GHA deploy with
  the full secret set) can only be closed on a working DEV with working CI.

Starting F3 metal now would put prod on code that has no current proof of working, with no CI to
catch regressions.

## Options considered

| Option | For | Against |
| --- | --- | --- |
| A - restore CI and DEV first, then F3 metal | every later step has a test baseline and CI; F9 gate items become closable | F3 starts later |
| B - start F3 metal now, fix CI and DEV in parallel | prod sooner | prod built without CI or a working DEV to compare with; F9 gate stays FAIL |

## Decision

Option A. Order: restore the dev runner and CI, recover DEV until `utils/run-tests.sh --env dev
--suite all` has no FAIL, close the DEV-side F9 gate items, then F3 metal.

## Consequences

- Two new steps precede F3 in the plan; no finished work is redone.
- The plan's todo statuses are reconciled with `docs/audit/2026-10-18-plan-audit.md` in the same
  revision.
- Pushes to `homelab-v2` will run CI again once the runner is back, including DEV apply and
  deploy workflows.

## Sources

- `docs/audit/2026-10-18-plan-audit.md` (CI history, runner checks, DEV test run of 2026-10-18)
- `knowledge/rebuild-drill-2026-09-10.md:48-55` (F9 gate)
- decided by the operator, 2026-10-18
