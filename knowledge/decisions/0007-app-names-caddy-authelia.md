Status: draft
Last reviewed: 2026-10-20
Scope: how the apps get names and TLS, and how Authelia sits in front of them, per environment

# 0007 - Serve the apps by name through Caddy with Authelia in front, on DEV and prod

## Context

- Apps answered only on `<host>:<port>` over plain HTTP; Authelia ran on DEV as a standalone portal
  for `homelab.local` that protected nothing, and prod ran without it
  ([0003](0003-prod-without-authelia.md)).
- The zone `dkhomelabserver.xyz` is on Cloudflare (`dig NS`: `jose`/`vivienne.ns.cloudflare.com`,
  2026-10-20); names inside the network come from AdGuard rewrites on OPNsense (`docs/network.md`).
- Ports 80 and 443 are free on `ubuntu-apps`; Grocery is public through the OPNsense HAProxy.

## Options considered

| Option | For | Against |
| --- | --- | --- |
| Caddy, config generated from `config/services.yml`, Authelia forward-auth | one source for names, ports and API exceptions; automatic HTTPS | one more container per env; a Cloudflare token for prod certificates |
| Keep IP:port | no work | no TLS, no single sign-on, bookmarks break when ports move |
| OPNsense HAProxy for every app | one proxy | router change for every app; no DEV equivalent |

## Decision

Profile `proxy` runs Caddy on the apps host with one wildcard site per env: `*.dev.dkhomelabserver.xyz`
on DEV (Caddy's internal CA), `*.dkhomelabserver.xyz` on prod (Let's Encrypt wildcard through the
Cloudflare DNS challenge, `CLOUDFLARE_API_TOKEN`). `utils/gen-proxy-config.py` writes the Caddyfile and
Authelia's session cookie and access rules from `config/services.yml` at deploy. Every name goes
through Authelia (`auth.<domain>`, one factor) except what a service lists in `auth_bypass`. Profile
`auth` runs on prod too, together with `proxy`. Grocery stays on the OPNsense HAProxy.

## Consequences

- Prod enables `auth` and `proxy` only when `CLOUDFLARE_API_TOKEN` is in environment `prod`; without
  it the deploy keeps profile `media` alone (no half-working HTTPS).
- API clients keep working through `auth_bypass`: Jellyfin entirely, Immich, Linkwarden and Trilium
  `/api`, Navidrome `/rest` (Subsonic); each app still checks its own login there.
- Names resolve through AdGuard rewrites (one per app, generated: `gen-proxy-config.py --file adguard`);
  the router change is `utils/f2-adguard-rewrites.sh`, run by the owner's decision.
- Authelia runs plain HTTP behind Caddy; the DEV self-signed certificate is gone.
- Supersedes [0003](0003-prod-without-authelia.md).

## Sources

- decided by the operator, 2026-10-20 (plan "Etap 2b - nazwy aplikacji, Caddy i Authelia")
- `utils/gen-proxy-config.py --self-test`; DEV checks with `curl --resolve` in the smoke suite
