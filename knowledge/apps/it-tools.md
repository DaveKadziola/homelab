# IT Tools

| | |
|--|--|
| URL | `https://it-tools.<domain>` (through Caddy + Authelia); DEV direct `http://192.168.122.50:8086` |
| Image | `corentinth/it-tools:2024.10.22-7ca5933` (last tagged release; static nginx) |
| Login | none (Authelia in front) |
| Config-as-code | yes |

Stateless converters and generators in the browser (hashes, encoders, UUIDs, JWT, cron, ...). No
volumes, no bootstrap. Added 2026-10-20 (owner).
