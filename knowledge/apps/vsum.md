# vsum (video summaries)

| | |
|--|--|
| URL (dev) | https://vsum.dev.dkhomelabserver.xyz (Authelia); http://192.168.122.50:8088 -> container `:8080` |
| Services | `vsum-web` (GUI, `/healthz` runs a database query), `vsum-worker` (channel feeds, one approved video at a time); profile `vsum` |
| Login | Authelia in front; the app's own login is off (`VSUM_AUTH` unset) |
| DB | `vsum` / role `vsum` / `VSUM_DB_PASSWORD` (core Postgres, daily dump) |
| Archive | named volume `vsum_archive` on DEV; prod `/mnt/homelab/media/video/vsum` (SA500 NFS, owner UID 10001, not backed up) |
| Trilium | `http://trilium:8080` with `VSUM_TRILIUM_TOKEN`; without the token the note export is off |
| Upstream | `DaveKadziola/video-summarizer` (private), pinned by `vsum_ref` in `deploy-core.yml`; contract: `docs/knowledge-base/deployment.md` there |

Deployed automatically when profile `vsum` is on: `deploy-core.yml` builds `vsum:<ref[:12]>` on the
host from the repository at `vsum_ref` (a new ref is a new tag, so it rebuilds), with
`VSUM_GIT_TOKEN` as the BuildKit secret `GIT_AUTH_TOKEN`, then `up` starts both services.
`postgres-init` creates database and role `vsum` and sets the role's password to `VSUM_DB_PASSWORD`
on every deploy. Without `VSUM_GIT_TOKEN` the deploy stops at an assert; remove `vsum` from the
profiles to deploy without it.

Followed channels never spend money on their own: a video runs only after someone approves it in the
GUI or pastes its link. Without `VSUM_OPENROUTER_KEY` or `VSUM_ELEVENLABS_KEY` the services run and a
video fails with a clear error.

`VSUM_PUBLIC_URL` is `https://vsum.<domain>` when profile `proxy` is on, else empty. An https URL
sets the `Secure` session cookie, so the forms (CSRF token in the session) work only through the
name, not through `:8088` over plain HTTP.

## Secrets made by hand

Generated: `VSUM_SECRET_KEY`, `VSUM_DB_PASSWORD` (`utils/gen-app-credentials.sh --env <env> --app vsum`).
The others come from their issuer. Store each in the runner cache, the GitHub environment and
Bitwarden; the value is read from the terminal and never printed:

```bash
umask 077; read -rs v; printf '%s' "$v" > ~/.homelab-secrets/dev/VSUM_GIT_TOKEN; unset v
gh secret set VSUM_GIT_TOKEN --env dev --repo DaveKadziola/homelab < ~/.homelab-secrets/dev/VSUM_GIT_TOKEN
./utils/bw-store.py --env dev VSUM_GIT_TOKEN
```

The same three lines for `VSUM_OPENROUTER_KEY`, `VSUM_ELEVENLABS_KEY` and `VSUM_TRILIUM_TOKEN` (create
it in that env's Trilium: Options -> ETAPI). Apps Deploy Dev runs the workflow file from `main`, so
until a release carries the `VSUM_*` lines of `apps-deploy-dev.yml` the DEV deploy reads them from the
runner cache `~/.homelab-secrets/dev/`.

## Turning it on in prod

1. The SA500 holds `hl-media` and is exported (one-time wipe, `knowledge/storage.md` "Attach and
   format"); `deploy-storage.yml` creates `media/video/vsum` owned by 10001.
2. RAM: the compose limits on prod already add up to more than the 8 GiB of `ubuntu-apps`; vsum adds
   960 MiB (worker 768m, web 192m; measured peaks 321 and 67 MiB). Decide what to lower or raise.
3. `envs: [dev, prod]` for the `VSUM_*` entries in `config/identities.yml`; generate and store the
   prod secrets as above.
4. Add `vsum` to `environments.prod.profiles` in `config/services.yml` and a vsum row (8088) to the
   application table of `knowledge/prod-target.md`.

Commands on the app host:

```bash
curl -s http://127.0.0.1:8088/healthz
docker logs homelab-core-vsum-worker-1 2>&1 | grep "worker started"
docker exec -it homelab-core-vsum-web-1 vsum --help
```
