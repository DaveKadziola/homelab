# Diun

| | |
|--|--|
| UI | none |
| Login | none |
| Config-as-code | yes |

Image-update watcher for container tags. Logs to stdout (Dozzle). Mails new tags to the env mailbox through the env's SMTP relay (`diun.env`, written by deploy-core; DEV: mailpit) - [monitoring](../monitoring.md). It does not see apt or the Ubuntu cloud image. Those are `utils/host-updates.sh` (the weekly timer): apt names, and the guest serial in `/etc/cloud/build.info` against `cloud-images.ubuntu.com/<codename>/current/unpacked/build-info.txt`. A newer serial means rebuilding the VM.

`compose/core/docker-compose.yml` pins an exact version per image (S5). Diun's `defaults.watchRepo` lists up to 5 newer release tags per repo (`x.y.z`, optional `v`, Jellyfin's `x.y.date-time`). Upgrading = change the tag in compose, PR, `Apps Deploy Dev`, tests, then prod. Exceptions: `omni-tools` publishes no tag for its current build, so it is pinned by digest (`latest@sha256:…`) and Diun reports only a new digest; `dumbwhois` has only `build-N` tags; the Postgres/Valkey images stay on a major (`16-alpine`, `8-alpine`, Immich's `14-vectorchord…`). The locally built `homelab-zotify:local` and `easy-todo-grocery-nodb` log "Cannot list tags" every run - expected, they are in no registry.
