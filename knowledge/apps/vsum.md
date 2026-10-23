Status: draft
Last reviewed: 2026-10-23
Scope: vsum on DEV and the steps to turn it on in prod - build, secrets, upstream releases

# vsum (video summaries)

| | |
|--|--|
| URL (dev) | https://vsum.dev.dkhomelabserver.xyz (Authelia); http://192.168.122.50:8088 -> container `:8080` |
| Services | `vsum-web` (GUI, `/healthz` runs a database query), `vsum-worker` (channel feeds, one approved video at a time); profile `vsum` |
| Login | Authelia in front; the app's own login is off (`VSUM_AUTH` unset) |
| DB | `vsum` / role `vsum` / `VSUM_DB_PASSWORD` (core Postgres, daily dump) |
| Archive | named volume `vsum_archive` on DEV; prod `/mnt/homelab/media/vsum` (SA500, folder `vsum` of the Samba share `media`, owner UID 10001, not backed up) |
| Trilium | `http://trilium:8080` with `VSUM_TRILIUM_TOKEN`; without the token the note export is off |
| Upstream | `DaveKadziola/video-summarizer` (private), pinned by `vsum_ref` in `deploy-core.yml`; contract: `docs/knowledge-base/deployment.md` there |

Deployed automatically when profile `vsum` is on: `deploy-core.yml` builds `vsum:<ref[:12]>` on the
host from the repository at `vsum_ref` (a new ref is a new tag, so it rebuilds), with
`VSUM_GIT_TOKEN` as the BuildKit secret `GIT_AUTH_TOKEN`, then `up` starts both services.
`postgres-init` creates database and role `vsum` and sets the role's password to `VSUM_DB_PASSWORD`
on every deploy. Without `VSUM_GIT_TOKEN` the deploy stops at an assert; remove `vsum` from the
profiles to deploy without it.

Releases: in the app repo work reaches `develop` through PRs and `master` only through a release
PR `develop` -> `master` that the operator merges (flow confirmed by the operator, 2026-10-23; not
enforced, rulesets need GitHub Pro for a private repository). A green CI run on `master` tags the
next `vX.Y.Z` with a GitHub release (`.github/workflows/ci.yml`); PR titles follow
`type(scope): subject`. First run: v1.0.0 on `3c0510b`, Release run 39962899518, 2026-10-23, still
from a direct PR into `master` without tests. Release PRs from `develop`: v1.0.2 on `fea21d2` (run
39968882819) and v1.1.0 on `37d88d6` (run 39973342538, a `feat` PR, so a minor bump), 2026-10-23.

Followed channels never spend money on their own: a video runs only after someone approves it in the
GUI or pastes its link. Without `VSUM_OPENROUTER_KEY` or `VSUM_ELEVENLABS_KEY` the services run and a
video fails with a clear error.

`VSUM_PUBLIC_URL` is `https://vsum.<domain>` when profile `proxy` is on, else empty. An https URL
sets the `Secure` session cookie, so the forms (CSRF token in the session) work only through the
name, not through `:8088` over plain HTTP.

## Secrets made by hand

Generated: `VSUM_SECRET_KEY`, `VSUM_DB_PASSWORD` (`utils/gen-app-credentials.sh --env <env> --app vsum`).
The others come from their issuer. Paste each one; the value is read from the terminal, hidden, and
goes to the runner cache, the GitHub environment and Bitwarden (queued while the vault is locked):

```bash
./utils/gen-app-credentials.sh --env dev --secret VSUM_GIT_TOKEN --paste
```

The same line for `VSUM_OPENROUTER_KEY`, `VSUM_ELEVENLABS_KEY` and `VSUM_TRILIUM_TOKEN` (create
it in that env's Trilium: Options -> ETAPI). Apps Deploy Dev runs the workflow file from `main`, so
until a release carries the `VSUM_*` lines of `apps-deploy-dev.yml` the DEV deploy reads them from the
runner cache `~/.homelab-secrets/dev/`.

`VSUM_OPENROUTER_KEY` must be a regular key from https://openrouter.ai/settings/keys, with a credit
limit. A management key (https://openrouter.ai/settings/management-keys) passes `GET /api/v1/key`
but gets 401 on chat completions (DEV, 2026-10-23); the DEV key is `vsum-homelab-dev`, limit 5 USD.

## Prod

Profile `vsum` is on in `environments.prod.profiles` since 2026-10-23; prod runs it after the next
release into `main`. That deploy creates `media/vsum` on the SA500 (owner 10001), builds the image and
starts both services behind Authelia as `vsum.dkhomelabserver.xyz`; the name needs
`./utils/adguard-rewrites.sh` once (router change, owner).

- Secrets: env `prod` has all six. A new ETAPI token comes from prod Trilium (http://192.168.50.30:8082,
  Options -> ETAPI) and is stored with
  `./utils/gen-app-credentials.sh --env prod --secret VSUM_TRILIUM_TOKEN --paste --rotate`.
- Open (owner): RAM. The compose limits on prod already add up to more than the 8 GiB of
  `ubuntu-apps`; vsum adds 960 MiB (worker 768m, web 192m; measured peaks 321 and 67 MiB).

Commands on the app host:

```bash
curl -s http://127.0.0.1:8088/healthz
docker logs homelab-core-vsum-worker-1 2>&1 | grep "worker started"
docker exec -it homelab-core-vsum-web-1 vsum --help
```
