Status: superseded by 0007-app-names-caddy-authelia.md
Last reviewed: 2026-10-20
Scope: whether prod runs Authelia before a proxy puts it in front of the apps

# 0003 - Run prod without Authelia until a proxy with forward-auth exists

## Context

- Authelia is configured for DEV only: cookie domain and access rules for `homelab.local`, portal
  `https://authelia.homelab.local:9091`, self-signed certificate for `192.168.122.50`
  (`compose/core/authelia/configuration.yml`, `ansible/playbooks/deploy-core.yml`).
- No proxy sends app traffic through Authelia (no forward-auth in `compose/`, `config/` or
  `ansible/`); every app has its own login. On DEV it is a standalone portal that protects nothing.
- The deploy enabled profile `auth` on every environment, so the first prod deploy would have
  started Authelia with the DEV domain and certificate (gap 6 in `knowledge/prod-target.md`).

## Options considered

| Option | For | Against |
| --- | --- | --- |
| Profile `auth` off on prod | nothing half-configured on prod; no change to DEV | no single sign-on on prod until a proxy exists |
| Prod Authelia config under `dkhomelabserver.xyz` | ready when a proxy comes | still protects nothing; a second config, certificate and AdGuard rewrites to maintain |
| Keep the DEV config on prod | no work | wrong cookie domain and certificate; login portal that cannot keep a session |

## Decision

The deploy enables profiles `media` on prod and `auth,media` on DEV (`COMPOSE_PROFILES` still
overrides both). Authelia comes to prod together with a proxy that puts it in front of the apps.

## Consequences

- The Authelia config and DEV certificate tasks run only when `auth` is enabled.
- `utils/bootstrap/authelia.sh` checks for the container before reading any secret, so prod reports
  SKIP.
- The prod `AUTHELIA_*` secrets stay in the GitHub environment `prod`; the deploy still passes them
  but nothing reads them.
- Enabling Authelia on prod later needs: a prod config (domain under `dkhomelabserver.xyz`), a
  certificate, AdGuard rewrites and the proxy rules.

## Sources

- decided by the operator, 2026-10-19 (gap 6: "switch off on prod")
- `ansible/playbooks/deploy-core.yml` (`compose_profiles`, the `auth` block); `ansible-lint` and a
  local Jinja evaluation of `compose_profiles`: prod -> `media`, dev -> `auth,media`
