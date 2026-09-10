# Security audit — 2026-09-10 (F9-F1)

**Scope:** DEV `ubuntu-apps-dev` @ `192.168.122.50` (libvirt). Physical prod VLANs were **unreachable** from the laptop (`192.168.20.20`, `.20.12`, `.50.30`, `.50.2` — no route). nmap-from-every-VLAN is therefore **SKIP** for prod.

**Tools**

| Tool | Result |
|------|--------|
| nmap 7.95 from libvirt `default` | ran — see exposure table |
| `docker inspect` on the apps guest | ran — no `privileged`; four Docker-socket mounts |
| gitleaks (working tree, `--no-git`) | 20 hits — all local `opnsense/backups/*.xml` (gitignored, **not** in git) |
| Trivy `config` on `compose/` | 1 HIGH: Zotify Dockerfile has no `USER` |
| Lynis | not installed — host hardening sampled via `sshd -T` / `ufw` / `iptables` |
| `./utils/run-tests.sh --env dev --suite config` | PASS=64 FAIL=0 |

**Format:** finding → severity → evidence → recommendation → status.

Status: `open` · `accepted` (known, live with it for now) · `mitigated` · `skip`.

---

## Exposure (DEV)

Listening on `0.0.0.0` (and `[::]`) on the guest. Confirmed open from the laptop unless noted.

| Port | Service | Auth today |
|------|---------|------------|
| 22 | SSH | pubkey only (`passwordauthentication no`) |
| 2283 | Immich | app login |
| 3001 | Linkwarden | app login |
| 4533 | Navidrome | app login |
| 5006 | Actual | first-run / none (F7 does not set) |
| 5050 | pgAdmin | app login |
| **5432** | Postgres | scram-sha-256 for remote; **published on all interfaces** |
| 7575 | Homarr | app login (CLI cannot converge) |
| 8080 | Dozzle | **none** + Docker socket |
| 8082 | Trilium | first-run / none |
| 8083 | Omni-tools | none |
| 8084 | DumbWhois | none |
| 8085 | BentoPDF | none |
| 8090 | Beszel | hub login |
| 8096 | Jellyfin | app login |
| 8101 | Grocery | app users |
| 8384 | Syncthing GUI | session login |
| 9000 / 9443 | Portainer | app login + Docker socket |
| 9091 | Authelia | self-signed TLS, username `admin` |
| 22000 | Syncthing sync | device IDs |
| **45876** | Beszel agent | host-network; unexpected if profile was “optional” |
| 4381 | Zotify OAuth | closed at scan time (only during login) |

DEV has **no host firewall** (`ufw` inactive, `INPUT` policy ACCEPT). That is acceptable on an isolated libvirt NAT **only**. The same compose on prod APP VLAN without OPNsense rules would expose Postgres and every UI to the VLAN.

---

## Findings

### S1 — Postgres published on `0.0.0.0:5432`

| | |
|--|--|
| Severity | **high** (prod) / medium (dev NAT) |
| Evidence | nmap open; `ss` `0.0.0.0:5432`; compose `5432:5432`; remote `psql` reaches scram (wrong password → FATAL, not “connection refused”) |
| Why | Grocery uses `host.docker.internal`. That does not require binding the LAN/VLAN. |
| Rec | Bind `127.0.0.1:5432:5432` on prod; keep a documented exception on DEV if grocery stays on the host network namespace. Cover with a smoke/net test. |
| Status | **open** |

### S2 — Docker socket in four containers

| | |
|--|--|
| Severity | **high** |
| Evidence | `docker inspect`: Portainer (rw), Dozzle (`:ro`), Diun (`:ro`), Beszel agent (`:ro`). None privileged. |
| Why | Socket = root on the host. Portainer is the intended control plane; Dozzle/Diun/Beszel are convenience. |
| Rec | Keep Portainer. Restrict Dozzle/Diun to the apps host / VPN. Do not publish Dozzle beyond the laptop/VPN. On prod, drop `:ro` mounts that are not needed or put them behind Authelia. |
| Status | **accepted** for Portainer; **open** for Dozzle published on `:8080` with no login |

### S3 — Authelia is not in front of the apps

| | |
|--|--|
| Severity | **high** |
| Evidence | `compose/core/authelia/configuration.yml` has `default_policy: one_factor` for `*.homelab.local` but **no** reverse proxy, no `forward-auth`, no per-app routers. Apps are reached by raw IP:port. TOTP disabled. |
| Rec | Prod: HAProxy/Caddy + Authelia forward-auth for every UI that is not grocery-public. DEV can stay IP:port if the libvirt net stays isolated. |
| Status | **open** (SSO is deployed, not integrated) |

### S4 — Authelia TLS is self-signed

| | |
|--|--|
| Severity | low (dev) / medium (if copied to prod) |
| Evidence | `openssl x509`: CN `authelia.homelab.local`, issuer=subject, SAN includes `192.168.122.50`, notAfter 2028-12-13 |
| Rec | DEV: keep + `/etc/hosts`. Prod: ACME on the proxy, not this cert. |
| Status | **accepted** on DEV |

### S5 — Almost every image is `:latest`

| | |
|--|--|
| Severity | **medium** (reproducibility + surprise break) |
| Evidence | `docker images` — Immich is the exception (`v3` / pinned postgres). Diun `latest` is 3 months old; DumbWhois 7 months. |
| Rec | Pin digest or a moving-but-explicit tag per service in compose; let Diun report newer tags. F10 can alert. |
| Status | **open** |

### S6 — Guest has no firewall

| | |
|--|--|
| Severity | **high** on prod / low on isolated DEV |
| Evidence | `ufw status: inactive`; `iptables INPUT policy ACCEPT` |
| Rec | Do not copy this guest to APP VLAN as-is. OPNsense must be the choke point; consider `ufw` default-deny on `ubuntu-apps` as defense in depth. |
| Status | **accepted** on DEV; **open** for prod |

### S7 — nmap from prod VLANs not possible

| | |
|--|--|
| Severity | — |
| Evidence | ping to `.20.20` / `.20.12` / `.50.30` / `.50.2` → UNREACHABLE |
| Rec | Repeat this audit from a WG peer and from IOT/APP after F3 metal is up. |
| Status | **skip** (scope) |

### S8 — Default / leftover credentials in unused Ansible

| | |
|--|--|
| Severity | **medium** (repo) |
| Evidence | `ansible/docker-containers.yml` still has `PGADMIN_DEFAULT_EMAIL: admin@local` and `PGADMIN_DEFAULT_PASSWORD: admin`. Playbook is not in `playbooks/`; `ansible-lint` does not see it. Not what `deploy-core.yml` applies. |
| Rec | Delete or quarantine the file. Never run it. |
| Status | **open** — marked deprecated in the same F9 change |

### S9 — OPNsense `config.xml` backups on the laptop

| | |
|--|--|
| Severity | **high** if copied or committed; **medium** at rest |
| Evidence | gitleaks: 20 findings in `opnsense/backups/config-20260701-*.xml` (API keys + private keys). Files are `0600`, gitignored, **not** tracked. |
| Rec | Import into Bitwarden (attachment), then `shred -u` the working copies. Do not `git add -f`. Rotate WG/OPNsense material if these files ever left the laptop. |
| Status | **open** (operator action — not deleted by this audit) |

### S10 — Secrets path is correct on the guest; Bitwarden unverified

| | |
|--|--|
| Severity | **medium** |
| Evidence | `/opt/homelab/secrets/dev` is `root:root` `0700`, files `0600`. `.env` is `ubuntu-dev:docker` `0640`. GH env `dev` has the F7 names. `bw` CLI absent — vault import not confirmed. GH is write-only. |
| Rec | Export cache → Bitwarden (`homelab/<NAME>/dev`), shred the staging file. See [`security.md`](security.md). |
| Status | **open** |

### S11 — Apps without F7 accounts

| | |
|--|--|
| Severity | **medium** |
| Evidence | Trilium, Actual: first-run UI passwords, not in `identities.yml`. Dozzle/Omni/DumbWhois/Bento: no auth. Homarr password is cache-aligned in sqlite but CLI cannot verify. |
| Rec | Document in Bitwarden or add bootstrap. Do not put Trilium/Actual on a shared VLAN without Authelia. |
| Status | **open** |

### S12 — SSH on the apps guest is in good shape

| | |
|--|--|
| Severity | info |
| Evidence | `passwordauthentication no`, `pubkeyauthentication yes`, `permitrootlogin without-password` (keys only) |
| Rec | Keep. Do not enable password SSH for convenience. |
| Status | **mitigated** |

### S13 — Zotify image runs as root

| | |
|--|--|
| Severity | low |
| Evidence | Trivy DS-0002 on `compose/core/zotify/Dockerfile` |
| Rec | Add a `USER` if the upstream CLI allows it. |
| Status | **open** |

### S14 — CI deploy workflows do not inject F7 secrets

| | |
|--|--|
| Severity | **high** (broken / partial deploys) |
| Evidence | `.github/workflows/apps-deploy-dev.yml` and `apps-deploy-prod.yml` only pass `POSTGRES_PASSWORD` + `LINKWARDEN_URL`. `deploy-core.yml` now asserts `HOMARR_SECRET_KEY`, `LINKWARDEN_SECRET`, `PGADMIN_PASSWORD` and writes every identity secret into `.env`. A clean runner without `~/.homelab-secrets` will fail or write empty values. `ci-validate.yml` `docker compose config` only sets `POSTGRES_PASSWORD` — compose `:?` vars will fail the job. |
| Rec | Pass every secret from the GH Environment. Add `tests-dev.yml` (missing). Fixed in the same F9 change for the two deploy workflows + validate placeholders. |
| Status | **mitigated** in repo (full secret env + `docker compose config` placeholders + gitleaks in `ci-validate`); confirm on the next GHA run |

### S15 — No image CVE scan in CI

| | |
|--|--|
| Severity | low |
| Evidence | Trivy used ad-hoc; Diun watches tags, does not gate deploys. Lynis absent. |
| Rec | Periodic `trivy image` on the apps host (F10), not a merge blocker. |
| Status | **accepted** |

---

## Authentication coverage (honest)

| Control | DEV today |
|---------|-----------|
| Network isolation | libvirt NAT — yes |
| Host firewall | no |
| VPN required | n/a (not on prod LAN) |
| Authelia SSO | portal only |
| Per-app admin | F7 bootstrap for the apps in `identities.yml` |
| Default passwords | leftover playbook only; live apps checked against cache 2026-09-10 |

---

## Repeat after F3 metal

1. nmap from WG, IOT, APP, WAN (expect only 443 grocery).
2. Confirm OPNsense rules vs this exposure table.
3. Re-run gitleaks in CI (`detect` on the git tree — should be clean).
4. Lynis on `ubuntu-apps` / `ubuntu-nas`.
