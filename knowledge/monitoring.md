Status: draft
Last reviewed: 2026-10-20
Scope: alerts and checks - Uptime Kuma, backup freshness, Beszel, Diun and the mail path per env

# Monitoring

Decision: [0006](decisions/0006-alerts-kuma-proton-smtp.md). Config: [`config/monitoring.yml`](../config/monitoring.yml).

| Piece | Where | What it alerts on | Config |
|--|--|--|--|
| Uptime Kuma | add-on on Home Assistant (prod T620 `:3001`, DEV twin `192.168.122.60:3001`) | a service, PVE, NAS, router or public Grocery does not answer; a backup stream is stale or silent | `utils/kuma-sync.py` from `monitoring.yml` + `services.yml` |
| Backup freshness | NAS, `homelab-backup-check.timer` 06:00 | pushes `up`/`down` per stream to its Kuma push monitor | `monitoring.yml` `backups` |
| Beszel | hub on the apps host | disk, RAM, CPU thresholds | `monitoring.yml` `thresholds`, `utils/bootstrap/beszel.sh` |
| Diun | apps host | new image tags (information, not an alert) | `compose/core/diun/diun.yml`, `diun.env` from deploy |

Mail: to `environment_email` (`config/identities.yml`). Prod: Proton SMTP (`smtp.protonmail.ch:587`,
STARTTLS) with `SMTP_USERNAME` / `SMTP_PASSWORD`; until they exist Kuma keeps its monitors but mails
nothing, Diun only logs. DEV: mailpit (profile `devmail`, UI `http://192.168.122.50:8025`) catches
every mail.

## Uptime Kuma

```bash
utils/kuma-sync.py --setup-venv          # once: venv ~/.local/share/homelab/kuma-venv (uptime-kuma-api 1.2.1)
~/.local/share/homelab/kuma-venv/bin/python utils/kuma-sync.py --env dev --dry-run
~/.local/share/homelab/kuma-venv/bin/python utils/kuma-sync.py --env dev
```

- Only monitors named `homelab:...` are touched; anything else in Kuma is left alone.
- A service check of `http` or `https` is a TCP port monitor. Kuma's HTTP client on the T620 aborts the response body (`response stream aborted`) and then mails that a live app is down (2026-10-22). Extra `http` monitors keep interval 60 s, maxretries 3, timeout 60 s.
- Profiles come from `config/services.yml` `environments.<env>.profiles`. Prod runs `auth` and `proxy`
  only with `CLOUDFLARE_API_TOKEN`; until then sync prod with `COMPOSE_PROFILES=media,beszel-agent`,
  or Kuma watches an Authelia and a Caddy that do not run.
- Without `SMTP_USERNAME`/`SMTP_PASSWORD` the sync still sets up the monitors, without the mail.
- Push token of a stream = first 24 hex characters of `sha256("<KUMA_PUSH_SECRET>:<stream>")`; the NAS
  gets `KUMA_PUSH_SECRET` from the deploy. A push monitor's heartbeat is the stream's max age, so a NAS
  that stops pushing also alerts.
- The add-on 0.19.4 runs Uptime Kuma 2.5.6 (DEV, 2026-10-20). The pinned `uptime-kuma-api` 1.2.1 was
  written for 1.23: the script waits for Kuma's first `info` event before any call (earlier requests
  are dropped), sends `conditions: []` on create (NOT NULL in 2.x) and writes the SMTP notification
  itself. Review the script before upgrading the library or the add-on.
- Login `admin` / `KUMA_ADMIN_PASSWORD`; a fresh Kuma is set up (SQLite, admin) by the first sync. An
  unclaimed Kuma makes its first visitor the admin, so on prod the deploy installs the add-on and
  leaves it stopped, also at boot (`boot: manual`); claim it from the laptop in one go:
  `utils/ha.py --env prod call hassio.addon_start --data '{"addon": "a0d7b954_uptime-kuma"}'` and
  right after it `~/.local/share/homelab/kuma-venv/bin/python utils/kuma-sync.py --env prod`. The next
  deploy sees it started and keeps it running at boot.
- Kuma runs on the T620, so a dead T620, router or uplink sends nothing (accepted, decision 0006).

## Backup freshness by hand

```bash
sudo env HOMELAB_CONFIG_DIR=/opt/homelab-nas/config python3 /opt/homelab-nas/utils/backup/check-fresh.py --env prod --dry-run
```

The storage test suite shows the same (`storage/backup/fresh-<stream>`).
