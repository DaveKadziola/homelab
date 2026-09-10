# Home Assistant (T620)

HAOS is **not** deployed from this repo. The T620 at `192.168.20.13` is a separate appliance.

This directory is a placeholder for any config-as-code we later export. Do not put tokens here.

## What this repo does (F5)

- `utils/backup/ha-pull.sh` copies the newest Supervisor backup when `ha_host` is set and `HA_TOKEN` exists.
- On DEV `ha_host` is empty — the job SKIPs.
- You cannot flash HAOS from the laptop. Install it on the T620, then create a long-lived token in the HA UI and store it as `homelab/HA_TOKEN/prod` + GH env prod.

## After HAOS is up

1. Create a Supervisor backup in the UI (or `ha backups new`).
2. Put `HA_TOKEN` in `~/.homelab-secrets/prod/` (and Bitwarden).
3. Nightly `homelab-backup.timer` on `ubuntu-apps` will pull the newest `.tar` into `/mnt/homelab/backups/homeassistant`.
