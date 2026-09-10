# Home Assistant

Not a Docker service in `compose/core`. Hardware: Dell T620 at `192.168.20.13` (IOT VLAN), greenfield HAOS — flashed on the box, not from this laptop.

| | |
|--|--|
| Host | `192.168.20.13` |
| UI | `http://192.168.20.13:8123` (when HAOS is installed) |
| Backup | `utils/backup/ha-pull.sh` (needs `HA_TOKEN`) |
| DEV | skipped — no `ha_host` in `config/storage.yml` |

See [`homeassistant/README.md`](../../../homeassistant/README.md).
