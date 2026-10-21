# Home Assistant configuration

Only `packages/` is managed from this repository: `utils/ha.py --env dev|prod deploy` replaces
`<config>/packages` on Home Assistant with it, checks the config and reloads. Everything the UI
writes stays on Home Assistant and is snapshotted, not overwritten
([knowledge/apps/homeassistant.md](../knowledge/apps/homeassistant.md)).

- One topic per package file; a package can hold any integration keys (`template:`, `automation:`,
  `sensor:`, ...). Keys that only load at start need a restart (`utils/ha.py call homeassistant.restart`).
- `homelab_meta.yaml` carries the deployed commit (`@REVISION@` is replaced by the deploy) - keep it.
- Never put tokens, passwords or personal data here: the repository is public. Use `!secret` and
  the `secrets.yaml` on Home Assistant.
- Try a change on the DEV twin first: `utils/ha.py --env dev deploy --dry-run`, then without.
