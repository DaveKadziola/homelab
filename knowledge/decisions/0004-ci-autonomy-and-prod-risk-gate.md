Status: draft
Last reviewed: 2026-10-20
Scope: how changes reach homelab-v2 and prod without a human click on every step

# 0004 - Auto-merge into homelab-v2 and approve prod only when the Terraform plan is risky

## Context

- A prod release needed three approvals of environment `prod`: `Infra Apply Prod` and the two jobs
  of `Apps Deploy Prod` (gh api `actions/runs/<id>/approvals`, runs 39477578847 and 39490864110).
- The approval came before any plan: `Infra Apply Prod` ran `terraform apply -auto-approve` with no
  saved plan, and the PR plan (`infra-plan.yml`) runs with `-refresh=false`, so drift was never
  shown before the click (`docs/f3-proxmox.md` "PR plan").
- Nothing enforced green checks on `homelab-v2`: PR #59 merged while its `Infra Plan Dev` run was
  still going (gh run list, 2026-10-20). No job had a timeout.
- Agents act with the owner's GitHub account (token scopes `repo`, `workflow`), so GitHub cannot tell
  an agent from the owner.

## Options considered

| Option | For | Against |
| --- | --- | --- |
| Keep three approvals | no work | a click per step; the chain waits for the owner; the Terraform click is still blind |
| Fold the tests into the deploy job (3 -> 2) | one file | still two clicks and a blind Terraform approval |
| Risk gate: approval only for a risky plan | no click for normal releases; the owner sees the real plan when it matters | a classifier to maintain; app changes reach prod without a stop |

## Decision

PRs into `homelab-v2` merge themselves when the required checks `validate` (CI Validate) and `plan`
(Infra Plan Dev) pass; the ruleset has no bypass actors. A release to prod stays a PR
`homelab-v2` -> `main` that the owner merges. `Infra Apply Prod` plans with refresh, classifies the
plan with `utils/tf-plan-risk.py` and stops in environment `prod-gate` (reviewer: the owner) only
when the plan is risky or the run was started with `gate=true`; the apply job plans again and applies
only a plan with the same digest. Environment `prod` keeps its branch policy `main` and loses its
reviewer once the new workflow has run on `main`.

## Consequences

- Safe: no-op, read, create or update of `proxmox_virtual_environment_file`. Risky: any change to
  a VM, every delete or replace (also of the `cloud_config` snippet: Proxmox gives it to the VM at
  each boot even though Terraform ignores `initialization`), import, forget and every type the script
  does not know. New resource types in `terraform/` are risky until the script names them.
- A digest mismatch fails the apply; the fix is "Re-run all jobs" (a failed-jobs re-run compares with
  the old digest again).
- Every job has a timeout; a hung required check would otherwise block every PR.
- Agents turn on auto-merge only after `Infra Plan Dev` shows no VM replace or destroy, never push to
  `homelab-v2` directly, never use `[skip ci]`, and never approve deployments, edit rulesets or
  environments, or merge into `main` without the owner's request (`PROJECT-CONTEXT.md` sections 3
  and 5). The gate stops accidental risky applies, not an agent that breaks these rules.
- With the laptop runner offline nothing merges into `homelab-v2`; the way out is the owner editing
  the ruleset.
- Settings: [`docs/manual-setup.md`](../../docs/manual-setup.md) "CI autonomy".

## Sources

- decided by the operator, 2026-10-20 (options "bramka ryzyka z ochroną main" and "auto-merge tak,
  bez obejścia")
- `.github/workflows/infra-apply-prod.yml`, `utils/tf-plan-risk.py --self-test`; a DEV plan through the
  classifier gave `risky=false` (2026-10-20)
- to verify on the first release: the gate skipped for a safe plan, a `gate=true` run that stops in
  `prod-gate`, Apps Deploy Prod without approvals after the reviewer is removed

## Update 2026-10-22

The owner kept a reviewer on the first job of `Infra Apply Prod` (`prod-approve`). That click is
the go-ahead for production: a successful apply starts `Apps Deploy Prod` with no second click.
A manual apps deploy has no fresh apply, so that workflow asks once. Later jobs keep
`environment: prod` for the secrets. `prod` has no reviewer. `prod-gate` is unchanged: a safe
plan with `gate` false skips it.
