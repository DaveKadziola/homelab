Status: draft
Last reviewed: 2026-10-22
Scope: why Uptime Kuma, Diun and Beszel stay three tools

# 0008 - Keep Kuma, Diun and Beszel separate

## Context

- Beszel 0.21.0 on `prod-apps` sets `UpdateAvailable` on a running container when a newer tag exists. It checks at most once an hour and skips digest-pinned images (`agent/docker_image_updates.go` in tag `v0.21.0`).
- The same agent mails from system alerts: the agent is down, CPU, memory, disk, a network monitor, SMART, ZFS and a systemd service (`internal/alerts/alerts.go` binds those). An image update is not one of them.
- A native Linux agent also lists pending apt, dnf or apk packages once an hour. It does not run inside a container, and it does not know FreeBSD `pkg` (`agent/package_updates.go`). The apps-host agent is the container `beszel-agent`, so it does not see that host's apt. OPNsense is FreeBSD.
- Kuma on the T620 watches app ports, the public Grocery URL and backup freshness, and mails when one fails. Beszel only knows whether its own agent is connected.
- Diun mails new image tags. That is the notification Beszel does not send.
- NIC CRC growth on Proxmox is a separate cron. Beszel's network sample is throughput, every 60 seconds (`defaultDataCacheTimeMs`).

## Options considered

| Option | For | Against |
| --- | --- | --- |
| Move Kuma and Diun into Beszel | one UI, one mail path | no mail on a new image tag; no backup-freshness or per-app port check; apt on the apps host and `pkg` on the router are invisible |
| Keep the three tools | each one already covers the gap the others have | two places show "a newer image exists" (Diun's mail and Beszel's container flag) |

## Decision

Kuma stays the uptime mailer. Diun stays the image-tag mailer. Beszel stays the host metrics board (CPU, memory, disk, NIC throughput, and SMART where a physical disk answers). Do not add Beszel network monitors for checks Kuma already makes.

## Consequences

- A newer container tag is mailed by Diun. Beszel only marks it on the container.
- Apt on the apps host is mailed by `utils/host-updates.sh` on Sunday. Beszel may list apt on the NAS and on Proxmox, because those agents are not containers.
- Dropping Kuma or Diun loses mail the hub does not send.

## Sources

- Beszel tag `v0.21.0`: `agent/docker_image_updates.go`, `agent/package_updates.go`, `agent/agent.go` (`defaultDataCacheTimeMs`), `internal/alerts/alerts.go`, `internal/hub/systems/system_smart.go` (SMART default one hour)
- Decided by the operator, 2026-10-22, after asking whether the three could be unified
