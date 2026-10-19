Status: verified
Last reviewed: 2026-10-19
Scope: F9-F3 rebuild drill on nested DEV - real wipe of ubuntu-apps-dev, rebuild from repo + vault + `rebuild.md`

# Rebuild drill - 2026-10-19 (F9-F3, nested DEV)

Second drill; the first one (`rebuild-drill-2026-09-10.md`) was a tabletop. This time
`ubuntu-apps-dev` (VMID 101) was destroyed (`qm destroy 101 --purge`, operator) and rebuilt with
`knowledge/rebuild.md`, variant "Nested DEV": steps 3 -> 4 -> 5 -> 6 -> 7 -> 9. DEV backups
(`/mnt/homelab/backups`, 47 MB) were copied to the laptop first, because the DEV NFS export lives
on the same guest.

**Result:** the rebuild works end to end, but **not from the runbook alone** - six gaps needed
investigation. Five were fixed in code the same night (#16-#19); the runbook now covers the rest.
The F9 gate item "rebuild completes using only repo + vault + `rebuild.md`" stays **open** until a
repeat drill passes without fixes.

## Timeline and evidence

| Step | What happened | Evidence |
| --- | --- | --- |
| 3 Terraform | `Infra Apply Dev` (triggered by a merge push) created the VM: `Plan: 1 to add, 0 to change, 0 to destroy`; no replace | run 39172758944 |
| 3 verify | guest up: Ubuntu 24.04.5, cloud-init done, 2 vCPU / 6 GB / 27 GB as tfvars | `cloud-init status`, `nproc`, `free`, `df` |
| 4-5 | 1st and 2nd `Apps Deploy Dev`: image pulls failed (`dial tcp [2a06:…]:443: network is unreachable`), then succeeded after the pulls completed | runs 39173058008, 39173299058 |
| 6 | bootstrap FAIL on a fresh install: Immich (`no admin user found`), Jellyfin 12.2.0 (`/Startup/User` 404), Portainer (HTTP 403) | run 39173999243 |
| 4 | after the bootstrap fixes: `UNREACHABLE … Timeout (12s) waiting for privilege escalation prompt`; `sudo -n true` took 5-10 s | runs 39174868336, 39175243197 |
| 4-6 | after #19: deploy job success, bootstrap 9 PASS + Homarr SKIP; post-deploy tests 137 PASS, 1 FAIL (grocery container missing) | run 39175811960 |
| 5 grocery | image built on the host from the app repo; DB role + database created; stack redeployed | `curl :8101` -> 200 |
| 7 restore | `todo_grocery` restored from the 2026-10-18 dump: 5 tables, 2 task rows | `psql` counts |
| 9 tests | `run-tests.sh --env dev --suite all`: 158 PASS, 1 FAIL (local-checkout artefact, below); `--suite restore`: 10 PASS | 2026-10-19 |

## Gaps found and what was done

| # | Gap | Fix |
| --- | --- | --- |
| 1 | Immich bootstrap only handled an existing admin | #17 - first-admin path |
| 2 | Jellyfin bootstrap wizard broke on 12.2.0 (images on `:latest`, finding S5) | #17 |
| 3 | Portainer CE now requires the one-time `setup_token` from its startup log | #18 |
| 4 | cloud-init never set a hostname; `ubuntu` not in `/etc/hosts`; every sudo waited 5-10 s | #19 |
| 5 | `deploy-storage.yml` reset `/opt/homelab/config` to root after `deploy-core.yml` | #16 |
| 6 | Grocery: image only ever built by hand; DB "prep once" had no commands; Portainer reported the stack "present" while its container could not start; Portainer "start" tried to pull the local image | `rebuild.md` step 5 now has the commands; automating it is open |
| 7 | Dumps are plain SQL without `--clean`: they restore only into an empty database, not into one the fresh deploy already created | `restore-pg.sh --replace [--owner]`; linkwarden and immich restored over a fresh deploy |
| 8 | New guest = new SSH host key; the old `known_hosts` entry breaks tests | `rebuild.md` step 3 |
| 9 | A merge to `homelab-v2` starts `Infra Apply Dev` / `Apps Deploy Dev` by itself; a parallel manual run would race | `rebuild.md` step 3 |

Not exercised: volume-tar restore (Immich uploads, app config volumes), Homarr password (SKIP as always), Zotify OAuth, Syncthing peers.

## Local-run artefact

`infra/ansible/check` FAILs ("Sync the bootstrap scripts") when the tests run from a working copy
that contains the git-ignored `utils/bootstrap/__pycache__/`: the playbook would copy it to the
host. Host scripts were identical to the repo, file by file. CI checkouts are clean.

## Gate (merge `homelab-v2` -> `main`)

- [x] Bitwarden holds the secrets - real values since 2026-10-18 (`utils/rotate-secrets.py`)
- [x] `tests/restore/` PASS on DEV (2026-10-18 and after the rebuild)
- [x] GHA deploy injects the full secret set and the DEV test workflow runs
- [x] Nested rebuild using only repo + vault + `rebuild.md` - repeat drill passed, see `rebuild-drill-2026-10-19b.md`
- [ ] nmap from WG/IOT/APP (S7) - needs prod
