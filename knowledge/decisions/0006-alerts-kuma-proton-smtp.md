Status: draft
Last reviewed: 2026-10-20
Scope: where alerts come from and how they reach the owner

# 0006 - Alert from Uptime Kuma on the T620 and mail through Proton SMTP

## Context

- No alert path existed: Diun logged new tags, Beszel had no notifier, backups were never checked for
  age (plan F10-A, `knowledge/prod-target.md` gap 7).
- The owner has a paid Proton plan; Proton SMTP works only for an address on a custom (sub)domain
  (proton.me/support/smtp-submission). The zone is on Cloudflare.
- The T620 runs Home Assistant OS on hardware separate from the Proxmox host; the NAS shares its
  subnet (IOT), the apps host (APP) cannot reach it.

## Options considered

| Option | For | Against |
| --- | --- | --- |
| Uptime Kuma add-on on the T620 + Proton SMTP from a subdomain | no third party; separate hardware sees the Proxmox host fail; the Proton app gives push | nobody alerts when the T620, the router or the uplink is down |
| SMTP relay (Brevo/Mailjet) + healthchecks.io | an external dead-man switch | alert content at third parties; more accounts |
| ntfy + healthchecks.io | phone push | public ntfy topics; two services |

## Decision

Uptime Kuma (add-on on Home Assistant; DEV: on the HAOS twin) checks every proxied service, the
Proxmox host, the NAS, the router and public Grocery, and holds one push monitor per backup stream
that `utils/backup/check-fresh.py` on the NAS feeds daily. Kuma, Diun and Beszel mail to
`environment_email` through Proton SMTP on prod (`SMTP_USERNAME`/`SMTP_PASSWORD`) and through mailpit on
DEV. `utils/kuma-sync.py` keeps Kuma's `homelab:` monitors equal to `config/monitoring.yml` and
`config/services.yml`.

## Consequences

- A dead T620, router or uplink is silent; accepted by the owner.
- Prod needs the owner's steps: the Proton subdomain (DNS records in Cloudflare), the address, SMTP
  tokens in Bitwarden and environment `prod`.
- Kuma's config lives in its own database (in the HA backup); `kuma-sync.py` restores the `homelab:`
  part from the repo.

## Sources

- decided by the operator, 2026-10-20 ("Uptime Kuma jako dodatek HA na T620 + subdomena proton")
- DEV twin 2026-10-20: add-on 0.19.4 runs Uptime Kuma 2.5.6; `kuma-sync.py --env dev` created 27
  monitors, a second run changed nothing; a push with a derived token answered `{"ok":true}`
