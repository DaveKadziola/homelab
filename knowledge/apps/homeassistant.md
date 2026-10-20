# Home Assistant

Not a Docker service in `compose/core`. Prod: HP t620 thin client at `192.168.20.13` (IOT VLAN),
HAOS 18.3 written with `xzcat haos_generic-x86-64-18.3.img.xz | dd` to the internal SSD from a
Xubuntu live session (Ventoy, UEFI, Secure Boot off), 2026-10-20. DEV: a twin HAOS 18.3 VM in the
laptop libvirt, `utils/dev-haos-vm.sh` ([decision 0005](../decisions/0005-home-assistant-as-code.md)).

| | prod | DEV |
|--|--|--|
| URL (UI and API) | `http://192.168.20.13` | `http://192.168.122.60` |
| Created by | owner (USB stick) | `utils/dev-haos-vm.sh` (`--dry-run`, `--undo`) |
| Owner account | the owner's own | `admin`, `HA_ADMIN_PASSWORD`, made by `utils/ha.py bootstrap` |
| `HA_TOKEN` | owner creates it in the HA profile (Security -> Long-lived access tokens) | made by `utils/ha.py bootstrap` |

HAOS 18.3 serves Home Assistant on port **80**; on the DEV twin 8123 only redirects there (live
probes 2026-10-20). `config/storage.yml` `ha_url` holds the URL per environment.

## Control from the laptop or CI

`utils/ha.py --env dev|prod <command>`: `status`, `state [entity]`, `call <domain.service> --data
'{...}'`, `check`, `reload`, `deploy`, `export-ui`, `restore-ui`, `backup`, `bootstrap`. Token and
keys come from the environment or `~/.homelab-secrets/<env>/` (`HA_TOKEN`, `HA_SSH_PRIV`,
`HA_BACKUP_PASSWORD`); values are never printed.

- Supervisor calls (add-ons, backups) go over the websocket command `supervisor/api`, the way the UI
  does it: the REST proxy `/api/hassio/...` answered 401 to a token for an add-on install (DEV,
  2026-10-20). Backup downloads still use the REST proxy.
- Files go through the **Terminal & SSH** add-on (`core_ssh`, `root@<host>:22`, key `HA_SSH_PRIV`;
  `bootstrap` publishes port 22 and installs the public half). The HA config is `/homeassistant`
  inside the add-on; its tar is busybox.

## Configuration as code

- The repo owns `homeassistant/packages/*.yaml` only. `deploy` replaces `<config>/packages` with
  them, adds `homeassistant: packages: !include_dir_named packages` to `configuration.yaml` once (a
  restart; it stops instead of guessing when a `homeassistant:` block exists without it), runs the
  config check (rolls back on failure) and `homeassistant.reload_all`.
- Proof of a deploy: `homelab_meta.yaml` defines `sensor.homelab_config_revision`, set to the commit;
  `deploy` and the `ha` test suite read it back.
- CI: `Apps Deploy Dev` / `Apps Deploy Prod` run `bootstrap` and `deploy` after `deploy-core`. On
  prod the step is skipped with a warning while `HA_TOKEN` is not in environment `prod`.
- What the UI writes (`automations.yaml`, `scripts.yaml`, `scenes.yaml`, `configuration.yaml`) is
  never overwritten. `export-ui --dest <dir>` stores a snapshot only when something changed (keep
  30); `restore-ui --src <dir> --version <stamp> [--file x.yaml] --dry-run` shows the diff, without
  `--dry-run` it copies back (previous files kept in `<config>/.restore-<stamp>/`), checks and
  reloads. Snapshots are not committed: the repository is public.

## Add-ons (installed by `utils/ha.py bootstrap`)

| Add-on | Slug | Port | Purpose |
|--|--|--|--|
| Terminal & SSH 10.5.0 | `core_ssh` | 22 | file access for deploy, export, restore |
| Uptime Kuma 0.19.4 | `a0d7b954_uptime-kuma` | 3001 | monitoring and alerts ([monitoring](../monitoring.md)) |

## Backups

`backup --dest <dir>` makes a full Supervisor backup protected with `HA_BACKUP_PASSWORD`, downloads it
as `ha-full-<stamp>.tar`, deletes it from HA and keeps the 2 newest. The NAS runs it nightly (see
[backup](../backup.md)). A restore needs the password: Settings -> System -> Backups -> upload.

See [`homeassistant/README.md`](../../homeassistant/README.md).
