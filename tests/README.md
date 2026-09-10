# `tests/` — automated infrastructure and deployment tests (F7-C)

> **Rule:** a phase is not done until its tests are green. `PASS` is evidence,
> `SKIP` is an honest "cannot check this here", `FAIL` is a defect.

Everything is driven by [`config/services.yml`](../config/services.yml) and
[`config/identities.yml`](../config/identities.yml). No port, container name or
secret name is written down in a test — adding a service means editing the
config, not the suites.

## Run

```bash
utils/run-tests.sh --env dev                       # all suites
utils/run-tests.sh --env dev --suite smoke         # one suite
utils/run-tests.sh --env prod --suite net
utils/run-tests.sh --env dev --json                # machine-readable, for CI
utils/run-tests.sh --env dev --json-out report.json  # table + JSON file
```

Exit status is `1` only when something **FAILed**. `SKIP` never fails a run, so
the same command works while physical prod is still being built.

Artifacts that are too big for the table (terraform plan, ansible log) are kept
in `/tmp/homelab-tests-<env>/` and referenced from the failure message.

## What each suite proves

| Suite | Proves | Needs |
|-------|--------|-------|
| `smoke/` | every service in `config/services.yml` exists as a container, is `Up` (not `Restarting`), publishes its declared host port, answers with one of its `expect` codes, and is not in a restart loop / OOM-killing processes | SSH to the env host, `docker` group |
| `infra/` | `terraform plan` reports no changes; terraform state matches the tfvars it was applied with; `ansible-playbook --check` changes nothing; the guest really has the RAM/CPU/disk/IP from `terraform.tfvars`; IP, gateway, VLAN and prefix match `docs/network.md` | terraform, ansible, Proxmox API token, deploy secrets |
| `net/` | public and host-side DNS resolve; a WireGuard peer has a recent handshake; the public HAProxy endpoint from `public_url` answers and its TLS certificate is not about to expire; APP→NAS `2049/111` is open and other APP→IOT paths are blocked | prod network for the firewall and HAProxy checks |
| `config/` | every secret named in `config/identities.yml` exists in the matching GitHub environment; no secret value is committed; no deployed file carries a literal fallback secret; `config/services.yml` agrees with `compose/` and with the port tables in `docs/` | `gh` authenticated; nothing else |

### Test ids

`<suite>/<subject>/<aspect>` — for example `smoke/immich/endpoint`,
`infra/terraform/plan`, `config/gh-secret/POSTGRES_PASSWORD`. Ids are stable, so
a failure can be grepped for in CI logs or the JSON report.

## When a check SKIPs

A skip always carries its reason. The ones that are expected today:

| Skip | Why |
|------|-----|
| `smoke/*`, `infra/vm/*`, `net/firewall/*` on `--env prod` | the physical host `192.168.50.30` is offline until F3 |
| `net/public/*` | the public endpoint goes through HAProxy on OPNsense, which needs the prod backend |
| `net/wireguard/handshake` | `wg0` runs on OPNsense; there is no WireGuard interface on the machine running the tests |
| `net/dns/internal` | dev has no internal DNS zone (`homelabdev.local` has no server) |
| `infra/terraform/plan` | no Proxmox API token, or the nested PVE is not running (`utils/ensure-dev-proxmox.sh`) |
| `infra/ansible/check` | `POSTGRES_PASSWORD` is not available, so the rendered `.env` cannot be compared |
| `<service>/port`, `<service>/endpoint` for `check: container` | Diun, Zotify and the Beszel agent have no HTTP listener to probe |
| a service whose `profile` is not in `COMPOSE_PROFILES` | it is intentionally not deployed |
| a service with `optional: true` that is missing | it needs a manual step first (Beszel agent needs a hub key) |

## Add a service — one edit

Append it to `config/services.yml`; every suite picks it up on the next run:

```yaml
  - name: mynewapp
    title: My New App
    priority: P1
    stack: core
    container: homelab-core-mynewapp-1   # <compose project>-<service>-1
    check: http                          # http | https | tcp | container
    port: 8111                           # host port, as published by compose
    path: /health
    expect: [200]
    profile: media                       # only if the compose service has one
    optional: false                      # true -> missing is a SKIP, not a FAIL
```

That gives you: a smoke check (container, stability, published port, endpoint), a
`config/compose/mynewapp` consistency check against `compose/`, and a
`config/docs/mynewapp` check against the port tables in `docs/`. Add
`public_url:` and the net suite also tests the public endpoint and its
certificate; add a `secret:` in `config/identities.yml` and the config suite
requires that secret in both GitHub environments.

Ports live in `config/services.yml` **first**, then in compose, then in docs —
`config/compose/*` and `config/docs/*` fail if that order is broken.

## How it is built

- **bash + `python3`.** The suites are bash (SSH, curl, docker, terraform,
  ansible); every YAML/HCL/Markdown parse happens in
  [`tests/lib/hlconfig.py`](lib/hlconfig.py), which needs only `pyyaml`. No
  pytest, no pip install, no `yq`.
- [`tests/lib/common.sh`](lib/common.sh) provides `report PASS|FAIL|SKIP <id>
  <message>`, the SSH/HTTP/TCP helpers and the "is the host reachable" cache. A
  suite never formats output itself; `utils/run-tests.sh` renders the table or
  the JSON.
- Records use `\x1f` as the field separator, not a tab: tabs are IFS whitespace,
  so bash `read` collapses runs of them and every service that omits an optional
  key would shift a column.
- One SSH connection per run (`ControlMaster`), one `docker inspect` for all
  containers.
- **Read-only.** `terraform plan` runs without `-out` and with `-lock=false`,
  ansible runs in `--check` mode, everything else is a fact query. Safe to run
  repeatedly; no app state is touched.
- On the prod runner (which lives on `ubuntu-apps` itself) "remote" commands
  detect that the target address is local and run directly instead of over SSH.

### Secret scanning without gitleaks

`gitleaks` is used when it is installed. Otherwise the built-in scan in
`hlconfig.py scan-secrets` looks at tracked files only and reports:

- private-key blocks and provider tokens (`ghp_`, `github_pat_`, `AKIA`, `xox*`)
- assignments to a secret-ish name whose value looks like a real literal:
  ≥12 characters, letters **and** digits, no path/variable/code characters, and
  not an obvious placeholder (`change-me`, `example`, a repeated filler string)
- a tracked `.env` (only `.env.example` is allowed)
- `default-credentials/<file>`: a deployed file under `compose/` or `ansible/`
  that carries a literal fallback secret (`${FOO_SECRET:-literal}`,
  `default('literal')` or a plain literal), because that is the value a deploy
  actually uses when the GitHub secret is absent

Argon2/bcrypt/sha-crypt hashes are not reported: Authelia's file backend keeps
the admin hash in `compose/core/authelia/users_database.yml` by design.

## CI

| Workflow | Trigger | Runner |
|----------|---------|--------|
| [`tests-dev.yml`](../.github/workflows/tests-dev.yml) | after `Apps Deploy Dev` (`workflow_run`), on push to `tests/`/`config/`, or manually | `homelab-dev` |
| `post-deploy-tests` job in [`apps-deploy-prod.yml`](../.github/workflows/apps-deploy-prod.yml) | after the prod deploy job (post approval) | `homelab-prod` |

Both upload the JSON report as a build artifact.

## Not covered yet

- **`tests/restore/` (plan item C4)** — deliberately deferred. Restoring
  `pg_dump` into a scratch database, a `vzdump` onto a throwaway VMID and an
  OPNsense config into a file needs the F5 backup streams to exist first, and
  the plan schedules it monthly rather than per push. It will be a fifth suite
  with its own schedule, not part of `--suite all`.
- **Authelia SSO coverage** — that a protected service actually redirects to
  Authelia is not asserted; the dev cookie domain is `homelab.local`, which only
  works with a hosts entry.
- **Application-level content** — the suites check that Immich, Jellyfin and
  friends answer, not that libraries, users or dashboards are correct. Whatever
  a bootstrap script creates should be verified by that script.
- **`nmap` from every VLAN / exposure audit** — belongs to the F9-F1 security
  audit, not to a per-deploy test.
