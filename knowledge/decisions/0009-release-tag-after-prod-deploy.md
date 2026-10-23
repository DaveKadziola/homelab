Status: draft
Last reviewed: 2026-10-23
Scope: when and how a prod release gets its tag and notes

# 0009 - Tag and release after a green prod deploy, with bullet-point notes

## Context

- Releases `v2.0.0` and `v2.1.0` were tagged by hand on the main merge commit about two minutes
  after the merge (`gh release list`, `git log -1 v2.1.0`), so a tag meant "merged", not "runs on
  prod". Their notes are one prose paragraph.
- A merge to `main` reaches prod only through Infra Apply Prod (one approval, `prod-gate` for a
  risky plan) and Apps Deploy Prod ([0004](0004-ci-autonomy-and-prod-risk-gate.md)); either can stop.
- Every change reaches `develop` (then `homelab-v2`) through a PR whose merge commit carries the PR title, and the
  titles follow `type(scope): subject` (checked for #151-#158).
- The default `GITHUB_TOKEN` is read-only; the prod runner (CT 110) also runs PR code for Infra
  Plan Prod ([security](../security.md)).

## Options considered

| Option | For | Against |
| --- | --- | --- |
| Tag by hand after the deploy | the version is chosen deliberately | easy to forget; prose notes |
| Tag at merge to `main` | simple trigger | the tag can point at code that never reached prod |
| Job after green post-deploy tests, version from PR types | the tag means "runs on prod"; nothing to remember | needs a write token in one job; the version follows the PR titles |

## Decision

Apps Deploy Prod ends with a `release` job that runs only when `post-deploy-tests` passed. It runs
on a GitHub-hosted `ubuntu-24.04` runner with `contents: write` and no secrets, and calls
`utils/release-notes.py`: the next `vX.Y.Z` after the newest tag (`!` or BREAKING CHANGE -> major,
any `feat` -> minor, else patch) and notes as bullets under Features, Fixes, Docs and Other, one
per PR (`scope: subject (#N)`), with a header naming the run and the release PR. A commit that
already has a tag gets no second release. No CHANGELOG file: the GitHub releases are the changelog.

## Consequences

- A tag is what prod runs; the newest tag is the commit to go back to.
- A PR title outside `type(scope): subject` lands under Other and counts as a patch.
- A wrong version or text is fixed by editing the release in GitHub; the job never moves a tag.
- The job is the only one in the repository with a write token, and it never runs on a self-hosted
  runner.

## Sources

- decided by the operator, 2026-10-23 (automatic tag after a green prod deploy, notes as bullets)
- `utils/release-notes.py --self-test`; preview on `origin/homelab-v2` gave `v2.2.0` with #151-#158
  in four groups; a simulated release merge on `main` gave `v2.2.0` and named the release PR
