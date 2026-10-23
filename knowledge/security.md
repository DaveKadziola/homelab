Status: draft
Last reviewed: 2026-10-21
Scope: identities, where secret values live (cache, GitHub, Bitwarden), rotation, known security edges

# Security

Operating model. Dated findings: [`security-audit-2026-09-10.md`](security-audit-2026-09-10.md).

## Identities

One real mailbox per environment (Proton):

| Env | Mailbox |
|-----|---------|
| dev | `dev-homelabnotifications@pm.me` |
| prod | `prod-homelabnotifications@pm.me` |

Apps that login by **email** use that mailbox. Apps that login by **username** use `admin`. Never use `*.local` as an email — pgAdmin refuses reserved TLDs.

Generator: `utils/gen-app-credentials.sh` → GH Environment secret + `~/.homelab-secrets/<env>/<NAME>` + Bitwarden (`utils/bw-store.py`, below). No staging file since 2026-10-20. Values never go in git. Argon2/bcrypt **hashes** may.

The Beszel agent key and token are issued by the hub and stay on the apps host (`compose/core/beszel-agent.env`, written by the bootstrap); they are not GitHub secrets.

## Auth coverage

| Layer | Today |
|-------|--------|
| Authelia | In front of every app name through Caddy (profiles `auth` + `proxy`, [decision 0007](decisions/0007-app-names-caddy-authelia.md)), one factor, except the paths in `auth_bypass`. Cookie domain `dev.dkhomelabserver.xyz` on DEV, `dkhomelabserver.xyz` on prod, where both profiles run only once `CLOUDFLARE_API_TOKEN` is in environment `prod` (`ansible/playbooks/deploy-core.yml` `compose_profiles`). The app ports stay published (Caddy's upstream is `host.docker.internal:<port>`, `utils/gen-proxy-config.py`), so `<host>:<port>` reaches each app directly, without Authelia. |
| App admins | Converged by `utils/bootstrap/*.sh` where the app has an API/CLI |
| SSH | Key-only to the apps guest. NAS and apps: X11 forwarding off (`/etc/ssh/sshd_config.d/10-homelab.conf`, written by the deploy). Root on the prod Proxmox host: own laptop key `~/.ssh/homelab_prod_pve_ed25519` since 2026-10-20; the DEV key `~/.ssh/homelab_dev_ed25519` (also GH `dev` `UBUNTU_DOCKER_SSH_PRIV`, an environment without reviewer) no longer logs in there. Lost key: console login with the root password |
| TLS | Caddy: DEV internal CA, prod Let's Encrypt wildcard `*.dkhomelabserver.xyz` through the Cloudflare DNS challenge (`utils/gen-proxy-config.py`); Authelia is plain HTTP behind it. Public grocery ACME is a prod HAProxy job. |

## CI on a public repository

Threat model, checked 2026-10-20 with `gh api` (sources at the end).

- The repository is public and both runners sit inside the home network: `homelab-dev-laptop` runs as the laptop user `kdzl`, whose home holds `~/.homelab-secrets/` and `~/.ssh/`; `homelab-prod-ci-runner` runs as `runner` in the unprivileged CT 110 `ci-runner` on IOT (`192.168.20.14`). A job can read whatever its runner user can read. Apps Deploy Prod writes the `ubuntu-prod` key (sudo on NAS and apps) to `~/.ssh/homelab_prod_ed25519` for its jobs and removes it at the end of each one (`if: always()`), so a later job on that runner, such as Infra Plan Prod of a PR, does not find it (S20; until 2026-10-23 the key stayed there).
- Fork PRs trigger `CI Validate` and `Infra Plan Dev` on the laptop runner and `Infra Plan Prod` on the prod runner, with the PR's own workflow files. Every external contributor's run waits for the owner (`approval_policy: all_external_contributors`); approving one hands its code a shell on that runner, so approve only after reading the whole diff, workflows included.
- Every `uses:` is pinned to a commit SHA and GitHub enforces it (`sha_pinning_required: true`): a moved or hijacked tag cannot change what runs. To update an action, take the commit of the new tag (`gh api repos/<owner>/<action>/commits/<tag> --jq .sha`) and replace the SHA and the version comment in every workflow. `GITHUB_TOKEN` is read-only by default and cannot approve PRs.
- Rulesets without bypass actors: `main` accepts changes only through a PR (0 approvals) and refuses force pushes and deletion; `homelab-v2` the same, plus required checks `validate` and `plan`.
- Environments: `dev` (branch `homelab-v2`, no reviewer) and `prod` (branch `main`; reviewer: the owner until the gated `Infra Apply Prod` has run on `main`) hold the deploy secrets. `dev-plan` and `prod-plan` have no rules and hold the plan secrets (`PVEAuditor` tokens, `TF_API_TOKEN`, the `UBUNTU_DOCKER_PASSWORD` hash). `prod-gate` (branch `main`, reviewer: the owner, no secrets) stops risky Terraform plans ([0004](decisions/0004-ci-autonomy-and-prod-risk-gate.md)).
- The owner is the only collaborator and agents act with the owner's account, so GitHub cannot tell them apart: reviewers, rulesets and the gate stop mistakes, not an agent that ignores `PROJECT-CONTEXT.md`.

Sources: `gh api repos/DaveKadziola/homelab/{actions/permissions,actions/permissions/workflow,actions/permissions/fork-pr-contributor-approval,rulesets/25494696,rulesets/25494699,environments,actions/runners,collaborators}`; `pct config 110`; `ps` on the laptop (2026-10-20). Host and network findings on prod: [security-audit-2026-10-20](security-audit-2026-10-20.md).

## Known sharp edges (will be in F9)

- Postgres `:5432` published on the apps host
- Docker socket mounted into Portainer and Dozzle
- Homarr CLI hung and once leaked a password on the host `ps` line — **rotated**. Never pass Homarr’s password on `docker exec` argv.

## Rotate a login

```bash
./utils/gen-app-credentials.sh --env dev --secret PORTAINER_ADMIN_PASSWORD --rotate
# copy lands in ~/.homelab-secrets/dev/, GH env `dev` and Bitwarden (or the queue below)
./utils/bootstrap/portainer.sh --env dev --host 192.168.122.50
```

Legacy one-file caches (`~/.homelab-portainer-dev-pass`, …) are stale. Use `~/.homelab-secrets/<env>/`.

## Bitwarden (mandatory copy)

GH cannot read secrets back. New values go to Bitwarden in the same run: `gen-app-credentials.sh`, `setup-rclone-pcloud.sh` and `bootstrap-proxmox.sh --set-token` call `utils/bw-store.py`, which upserts the note from the cache file (the value reaches `bw` on stdin, never in argv; an unchanged note is not rewritten). `utils/rotate-secrets.py` writes Bitwarden itself and refuses `--apply` while the vault is locked. (checked 2026-10-20: `--self-test` against a fake `bw`, the locked path with `BW_SESSION` unset, and the real vault - see the sync line below)

Unlock before generating and the copy lands at once:

```bash
# CLI lives in ~/.local/bin/bw (official 2025.9.0)
export PATH="$HOME/.local/bin:$PATH"
bw login          # email + master password + 2FA — interactive
export BW_SESSION="$(bw unlock --raw)"
```

With the vault locked or `bw` missing the generator still succeeds: the names (never values) go to `~/.homelab-secrets/.bw-pending` and one line says so. After unlocking:

```bash
./utils/bw-store.py --pending                # store what was queued
./utils/bw-store.py --env all --dry-run      # whole cache (dev, prod, prod-plan): create / update / unchanged
./utils/bw-store.py --env all
bw lock
unset BW_SESSION
```

Notes are named `homelab/<NAME>/<env>` in folder `homelab`. The script never prints values. `utils/sync-cache-to-bitwarden.sh` is a wrapper for `bw-store.py`.

Operator sync: **2026-10-20**: `bw-store.py --env all --dry-run` against the real vault found 43 of the 44 cache values unchanged (dev 20, dev-plan 1, prod 22, prod-plan 1, including `RCLONE_CONFIG`) and `PROXMOX_API_TOKEN_SECRET/prod` to update: the token was made 2026-10-19 21:57, before `bw-store.py` existed (#45, merged 2026-10-20 01:49), so the vault kept an older value and nothing was queued. The cache value is the live one (HTTP 200 from the PVE API); `bw-store.py --env prod PROXMOX_API_TOKEN_SECRET` wrote it and the next dry run found all 44 unchanged (operator). The queue `~/.homelab-secrets/.bw-pending` is gone since. A secret made before 2026-10-20 can lag in the vault: run the dry run after an unlock. Earlier full sync 2026-09-11 (`--env all`). Vault also holds `POSTGRES_PASSWORD` / F1 leftovers (operator confirmed). Locked on this laptop; no session in the repo or chat.

Staging `~/homelab-bitwarden-*.txt` shredded the same day.

## rclone / pCloud (prod offsite)

```bash
rclone config create pcloud pcloud    # browser OAuth, one time
./utils/setup-rclone-pcloud.sh --push-gh   # also stores ~/.homelab-secrets/prod/RCLONE_CONFIG in Bitwarden
```

DEV does not push offsite (`storage.yml` `rclone: false`).
