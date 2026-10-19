# Home Assistant

Not a Docker service in `compose/core`. Hardware: HP t620 thin client at `192.168.20.13` (IOT VLAN), greenfield HAOS — flashed on the box, not from this laptop.

Installed 2026-10-20: HAOS 18.3 written with `xzcat haos_generic-x86-64-18.3.img.xz | dd` to the internal SSD from a Xubuntu live session (Ventoy, UEFI, Secure Boot off).

| | |
|--|--|
| Host | `192.168.20.13` |
| UI | `http://192.168.20.13:8123` (when HAOS is installed) |
| Backup | `utils/backup/ha-pull.sh` (needs `HA_TOKEN`) |
| DEV | skipped — no `ha_host` in `config/storage.yml` |

See [`homeassistant/README.md`](../../homeassistant/README.md).
