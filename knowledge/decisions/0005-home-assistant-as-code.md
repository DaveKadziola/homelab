Status: verified
Last reviewed: 2026-10-20
Scope: how Home Assistant is controlled, configured from the repo, tested on DEV and backed up

# 0005 - Manage Home Assistant packages from the repo, test them on a HAOS twin, snapshot the UI files

## Context

- HAOS 18.3 runs on the T620 (`192.168.20.13`), installed by hand; the repo had only a placeholder
  `homeassistant/` and a backup pull that hard-coded port 8123 and the Supervisor REST proxy
  (`utils/backup/ha-pull.sh`).
- HAOS 18.3 serves HA on port 80 (prod and the DEV twin, 2026-10-20). The Supervisor REST proxy
  refuses add-on installs to a long-lived token (HTTP 401); the websocket `supervisor/api` command
  accepts them (DEV twin, 2026-10-20).
- The repository is public; automations name devices and entities.

## Options considered

| Option | For | Against |
| --- | --- | --- |
| Repo owns `packages/`, UI files snapshotted | UI edits keep working; repo changes are reviewed and tested | two places for config |
| Repo owns all YAML | one source | every UI edit is overwritten by the next deploy |
| DEV twin as HA Container | light | no Supervisor, add-ons or Supervisor backups to test |
| DEV twin as HAOS VM | same Supervisor, add-ons and backups as prod | 2 GiB RAM and ~5 GB disk on the laptop |

## Decision

`utils/ha.py` controls HA (API token) and writes files through the Terminal & SSH add-on. The repo
owns `homeassistant/packages`; `deploy` checks the config and rolls back on failure. The UI files are
exported as snapshots on the NAS and restored only on request. DEV runs a HAOS VM twin of the T620
(`utils/dev-haos-vm.sh`).

## Consequences

- `HA_TOKEN` on prod is made by the owner; on DEV `bootstrap` onboards the twin and makes it.
- The first prod deploy adds the packages include to `configuration.yaml` and restarts HA once.
- Prod gets the add-ons Terminal & SSH and Uptime Kuma from the first release with `HA_TOKEN` set.
- UI snapshots and HA backups stay on the NAS (and offsite), never in git.

## Sources

- decided by the operator, 2026-10-20 ("HAOS VM na laptopie"; "tylko katalog packages/ ... yamle z GUI
  synchronizować, żeby nie nadpisywać, tylko móc przywrócić"; "timer na NAS")
- DEV twin 2026-10-20: `utils/ha.py --env dev bootstrap` (onboarding, token, add-ons), `deploy`
  (`sensor.homelab_config_revision` = commit), `export-ui`, `restore-ui --dry-run`, `backup` (full,
  protected backup with core 2026.10.2 and both add-ons); `utils/run-tests.sh --env dev --suite ha`
  5 PASS
