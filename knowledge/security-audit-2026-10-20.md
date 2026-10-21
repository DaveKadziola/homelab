Status: verified
Last reviewed: 2026-10-20
Scope: read-only security audit of the prod homelab (Proxmox host, ubuntu-nas, ubuntu-apps, CT 110 runner, Home Assistant T620, OPNsense, switch); closes F9 item S7 for LAN, IOT and APP; re-statuses S1-S15 of `security-audit-2026-09-10.md`

# Security audit - 2026-10-20 (F9, prod)

Repeat of [`security-audit-2026-09-10.md`](security-audit-2026-09-10.md) on the built prod system. All
commands were read-only: no config change, no package install, no restart, nothing written on a host.
Scans were TCP connect scans (`nmap -sT -Pn`) against the homelab hosts only, never a whole /24 (IOT
holds Tuya devices). Times are UTC, 2026-10-20 21:43-22:10. Code at `7ce5f05`.

## Summary

S7 is done for LAN, IOT and APP; WireGuard and WAN could not be tested from here. APP is closed as
documented: it reaches the NAS on 22/111/2049 and DNS, nothing else. IOT is the weak side: the IOT
rule passes everything except HOMEOFFICE and GUEST, so any IOT device (Tuya included) reaches the
router's SSH, GUI and AdGuard UI on all its addresses, the LAN, and every app port on `ubuntu-apps`.
The same devices share L2 with the Proxmox host, the NAS and HA, none of which runs a host firewall.
On that surface the router and the Proxmox host accept root logins with a password, and two prod apps
(Actual, Trilium) are not initialised, so the first visitor sets their password. Dozzle and Postgres
are open as S1/S2 said. The CI side is in good shape (fork approval, SHA pinning, read-only default
token, unprivileged runner with inbound drop).

## Method and tools

| Tool | Where | Result |
|------|-------|--------|
| nmap 7.95 `-sT -Pn -p-` | laptop `192.168.1.100` (LAN) | `-T4` pass lost ports, repeated at `-T3`; see note below |
| nmap 7.95 `-sT -Pn -p-`, `-sU` on a few ports | Proxmox host `192.168.20.20` (IOT, `vmbr0.20`) | output streamed back over SSH, no file on the host |
| bash `/dev/tcp` loop, `dig` | `ubuntu-apps` `192.168.50.30` (APP) | no nmap there, none installed |
| `nmap --script smb-protocols` | laptop and Proxmox host | positive control for Samba `hosts allow` |
| `curl` without credentials | laptop | app first-run state, HA endpoints |
| `sshd -T`, `ss`, `pveum`, `nft`, `sockstat`, `pfctl`, `pkg audit` | each host | see host review |

Scan note: through the router about 20% of the SYNs got no answer even on hosts with no firewall
(`192.168.20.20` `-T3`: 52018 closed, 13513 "filtered"); from the same L2 there were none
(`192.168.20.12` from IOT: 65526 closed, 0 filtered). The first `-T4` LAN pass missed listeners that
`ss` shows (NAS 59513, apps 5006). The `-T3` pass found every non-loopback `ss` listener on the
Proxmox host, NAS and apps, which is the validity check for the tables below. HA has no shell here,
so its list may still be incomplete from LAN (5355 was seen only from IOT).

## S7 - reachability per source network

### From LAN (laptop `192.168.1.100`)

`nmap -sT -Pn -p- -T3 --max-retries 3 --open` (21:50-21:56); switch: `--top-ports 1000`.

| Target | Open TCP | Expected? |
|--------|----------|-----------|
| `192.168.20.20` Proxmox | 22, 111, 3128, 8006 | 22, 8006 yes. 111 (rpcbind) and 3128 (spiceproxy) are in no exposure table |
| `192.168.20.12` NAS | 22, 111, 445, 2049, 33227, 38147, 41671, 53121, 59513 | 445 yes (SMB 3.1.1 negotiates from LAN). NFS 2049/111 and the mountd/statd ports are documented for APP only; the export itself is limited to `192.168.50.0/26` |
| `192.168.20.13` HA | 80, 111, 4357, 18555 | 80 yes. 4357 is the HA observer page (unauthenticated, HTTP 200); 111 and 18555 undocumented |
| `192.168.20.14` CT 110 | none (all filtered) | yes - nftables `policy drop` |
| `192.168.50.30` apps | 22, 111, 2283, 3001, 4533, 5006, 5050, 5432, 7575, 8080, 8082, 8083, 8084, 8085, 8090, 8096, 8101, 8384, 9000, 9443, 22000 | matches the port list in `prod-target.md` section 4; 5432 and 8080 are S1/S2. 4381 closed (Zotify idle), 9091 closed (no Authelia on prod) |
| `192.168.1.1` router | 22, 53, 80, 443, 853, 8443, 53530 | 22/443 yes (LAN admin, anti-lockout). 80 = AdGuard login (`302 /login.html`), 8443 AdGuard HTTPS, 853 DoT, 53530 unbound - none in `docs/network.md` |
| `192.168.1.2` switch | 80 | admin login over HTTP (`<title>Redirect to Login</title>`); undocumented |

UDP from LAN (no root on the laptop, so no `-sU`): `dig @192.168.1.1` answers over UDP and TCP; NTP
query to `192.168.1.1` answers (stratum 2); no NTP on `.20.20`, `.20.12`, `.50.30`. UDP 51820 not
tested (WireGuard does not answer unauthenticated packets).

### From IOT (Proxmox host `192.168.20.20`)

`ssh root@192.168.20.20 'nmap -sT -Pn -T3 --max-retries 3 -p- --open -oN - ...'` (21:57-22:00), then
short port lists and `-sU` (22:00-22:10).

| Target | Open | Expected? |
|--------|------|-----------|
| `192.168.20.12` NAS | TCP 22, 111, 445, 2049, 33227, 38147, 41671, 53121, 59513; UDP 111 | 445 accepts TCP but no SMB dialect comes back (`smb-protocols` empty; from LAN: `3:1:1`), so `hosts allow` holds. 22/111/2049 are open to every IOT device: same L2, no host firewall |
| `192.168.20.13` HA | 80, 111, 4357, 5355, 18555 | 80 yes; rest as above |
| `192.168.20.14` CT 110 | none | yes |
| `192.168.50.30` apps | same 21 TCP ports as from LAN; UDP 111 open, 21027/22000 open\|filtered | documented ("IOT can open APP", `prod-target.md` section 4), but it puts Postgres, Dozzle and the first-run apps in reach of IoT devices (S16) |
| `192.168.20.1`, `192.168.1.1`, `192.168.50.50` router | TCP 22, 53, 80, 443, 853, 8443, 53530 on each; UDP 53, 123 open, 51820 open\|filtered | **no** - `docs/network.md` lists DNS to `opt3ip` for IOT; SSH, GUI and AdGuard UI were not meant for IOT (S16, S17) |
| `192.168.1.100` laptop | none open; 3000 answers RST in two runs | IOT -> LAN is routed (pf passes it); the laptop drops the rest (unverified: no root on the laptop to read its ruleset) |
| `192.168.1.2` switch | 80 | no |

### From APP (`ubuntu-apps` `192.168.50.30`)

Bash `/dev/tcp` probe, 3 s timeout, ports 22 53 80 111 443 445 853 2049 3001 3128 4357 8006 8123 8443
9000 9091 (21:50). Everything not listed timed out (filtered).

| Target | Open | Expected? |
|--------|------|-----------|
| `192.168.20.20` Proxmox | none | yes |
| `192.168.20.12` NAS | 22, 111, 2049 | 111/2049 yes. 22 is the `.50.30 -> NAS` rule that `docs/network.md` marks unused, still loaded (S26) |
| `192.168.20.13` HA | none | yes |
| `192.168.20.14` CT 110 | none | yes |
| `192.168.20.1`, `192.168.1.1` | 53 (TCP) | yes - the DNS rdr to AdGuard; UDP to these times out, as `docs/network.md` "DNS rule of thumb" says |
| `192.168.50.50` router (APP) | 53 | yes; SSH, GUI and AdGuard UI not reachable from APP |
| `192.168.1.100` laptop | none | yes |

`dig @192.168.50.50` and `dig @1.1.1.1` both return the AdGuard rewrite (`192.168.20.20`), so the
redirect works from APP.

### From WireGuard and WAN

Not done, see "Not done".

## Host review

### Proxmox host `192.168.20.20`

- `pveversion`: `pve-manager/9.2.21`, kernel `7.0.14-25-pve`. `apt list --upgradable`: 0 (package
  lists from 2026-10-20 01:41 local). Enterprise repos `Enabled: no`, `pve-no-subscription` in use.
- `sshd -T`: `permitrootlogin yes`, `passwordauthentication yes`, `pubkeyauthentication yes`,
  `kbdinteractiveauthentication no`, `x11forwarding yes` (`/etc/ssh/sshd_config:33 PermitRootLogin yes`).
  An unauthenticated client is offered `publickey,password`.
- Root `authorized_keys` (`/etc/pve/priv/authorized_keys`): 2 keys, `root@proxmox` and
  `homelab-prod-pve`. The DEV key `~/.ssh/homelab_dev_ed25519` is refused
  (`Permission denied (publickey,password)`), as `security.md` says.
- `journalctl -u ssh --since -7days`: 7 password logins and 4 failed passwords for root, all from
  `192.168.20.101` (its router DHCP lease carries the MAC of the laptop's `wlan0`, on IOT Wi-Fi);
  254 key logins from the laptop. None from the runner `192.168.20.14`, although `Infra Apply Prod`
  succeeded three times on 2026-10-20 (`gh run list --branch main`).
- `pveum user list`: `root@pam`, `homelab-prod@pam` (no Linux account, so no PAM password login).
  `pvesh get /access/tfa`: no TFA entries for any user.
- Tokens: `homelab-prod@pam!terraform` `privsep=0`; `homelab-prod@pam!plan` `privsep=1`.
  `pveum acl list`: `/` `homelab-prod@pam` `Administrator`; `/` `homelab-prod@pam!plan` `PVEAuditor`.
  With `privsep=0` the Terraform token has full Administrator.
- `pve-firewall status`: `disabled/running`; `iptables -S INPUT`: `-P INPUT ACCEPT`, no nft tables.
- `ss -tlnp` (non-loopback): 22 sshd, 111 rpcbind, 3128 spiceproxy, 8006 pveproxy.

### ubuntu-nas `192.168.20.12`

- Ubuntu 24.04.5, kernel 6.8.0-147. `sshd -T`: `permitrootlogin without-password`,
  `passwordauthentication no`, `pubkeyauthentication yes`, `x11forwarding yes`. One key
  (`homelab-prod`) for `ubuntu-prod`, none for root; root password locked (`passwd -S root`: `L`).
- `sudo -n -l`: `ubuntu-prod` has `(ALL) NOPASSWD: ALL`.
- `ufw status`: inactive; `nft list ruleset`: empty; `iptables INPUT` policy ACCEPT.
- `ss -tlnp`: 22, 111, 445 smbd, 2049, mountd/statd ports, all on `0.0.0.0`/`[::]`.
- `/etc/exports`: `/export 192.168.50.0/26(rw,sync,no_subtree_check,no_root_squash,crossmnt)`.
- `testparm -s`: `server min protocol = SMB3`, `hosts allow = 192.168.1.0/24 10.10.10.0/24 127.0.0.1`,
  `hosts deny = ALL`, shares `share`, `media`, `backups` with `valid users = homelab-smb`.
- `apt list --upgradable`: 4, all `noble-security` (`ca-certificates`, `liblzma5`, `python3-jwt`,
  `xz-utils`); `unattended-upgrades` enabled, `APT::Periodic::Unattended-Upgrade "1"`.

### ubuntu-apps `192.168.50.30`

- Ubuntu 24.04.5, kernel 6.8.0-147. SSH, keys, sudo, root password: same as the NAS.
- `ufw status`: inactive; `iptables -S INPUT`: policy ACCEPT; Docker's own nft tables only.
- `docker ps`: 22 containers; every published port is on `0.0.0.0` and `[::]` (list in the LAN table).
- `docker inspect`: none privileged; Docker socket in Portainer (`rw`), Dozzle (`ro`), Diun (`ro`).
  Beszel agent is not running.
- Images: explicit tags, except `iib0011/omni-tools:latest` pinned by digest
  (`compose/core/docker-compose.yml:155`) and two local builds (`easy-todo-grocery-nodb:latest`,
  `homelab-zotify:local`).
- `/opt/homelab/secrets`: `root:root` `drwx------`, 0 files not `0600`;
  `compose/core/.env`: `ubuntu-prod:docker` `0640`.
- NFS: `192.168.20.12:/export` on `/mnt/homelab`, `vers=4.2`, `sec=sys`.
- Pending upgrades: the same 4 security packages as the NAS; `unattended-upgrades` enabled.
- Unauthenticated `curl` from the laptop:
  - Dozzle `:8080`: HTTP 200, page config `authProvider":"none"`, `/api/version` 200.
  - Actual `:5006/account/needs-bootstrap`: `"bootstrapped":false`.
  - Trilium `:8082/api/setup/status`: `"isInitialized":false`, `"authRequired":false`.
  - Portainer `/api/users/admin/check`: 204 (admin exists).
  - Syncthing `/rest/system/status`: 403.

### CT 110 `ci-runner` `192.168.20.14`

- `pct config 110`: `unprivileged: 1`, `features: nesting=1`, `vmbr0` tag 20, Debian 13.
- `pct exec 110 -- nft list ruleset`: `inet filter input policy drop`, accepts only `lo`,
  established/related and ICMP. `ss -tlnp`: only `127.0.0.1:25` / `[::1]:25`. No sshd.
- The runner (`Runner.Listener`, `RunnerService.js`) runs as `runner` (uid 1000, no extra groups);
  `sudo` is not installed.
- `/home/runner/.ssh/homelab_prod_ed25519` (`0600 runner`) is the key that logs into NAS and apps as
  `ubuntu-prod`, which has `NOPASSWD: ALL` there.
- `apt list --upgradable`: 0; `unattended-upgrades` enabled.
- GitHub (`gh api`): repository `PUBLIC`; Actions `allowed_actions: all`,
  `sha_pinning_required: true`; fork PR approval `all_external_contributors`;
  `default_workflow_permissions: read`, `can_approve_pull_request_reviews: false`. Runners
  `homelab-dev-laptop` and `homelab-prod-ci-runner` online.

### OPNsense router

- `opnsense-version`: `OPNsense 26.1.9`; `freebsd-version -ku`: `14.3-RELEASE-p14`.
- `/usr/local/etc/ssh/sshd_config`: `PermitRootLogin yes`, `PasswordAuthentication yes`,
  `ChallengeResponseAuthentication yes`, `AllowGroups wheel`. `sshd -T`: `listenaddress 0.0.0.0:22`
  and `[::]:22`, `kbdinteractiveauthentication yes`. An unauthenticated client is offered
  `publickey,password,keyboard-interactive`. `/etc/pam.d/sshd` uses `pam_opnsense.so` (`sufficient`),
  and the `root` user in `/conf/config.xml` has a password set (value not read). Root
  `authorized_keys`: one key (`daveadmin`).
- GUI: `<webgui>` has `protocol https` and no `<interfaces>`, so lighttpd listens on `*:443`
  (`sockstat`); GUI `authmode` is `TOTP Server,Local Database`; one user carries an OTP seed.
- `sockstat -4 -l`: sshd `*:22`, lighttpd `*:443`, AdGuard `*:53`, `*:80`, `*:853`, `*:8443`,
  unbound `*:53530`, ntpd on every interface address, haproxy `192.168.100.2:443`, WireGuard
  `*:51820`, dhcpd `*:67`.
- `pfctl -sr | wc -l`: 129 rules; `pfctl -sn | wc -l`: 39. IOT rule:
  `pass in quick on vlan03 inet from (vlan03:network) to ! (NotForIOT:network)`, where
  `NotForIOT` = `vlan02` (HOMEOFFICE) + `vlan04` (GUEST). APP rules: NFS and sunrpc to `.20.12`,
  SSH from `.50.30` to `.20.12`, and `to ! <PrivateNetworks>`.
- `pkg audit -q` (local `vuln.xml` of 2026-10-18): 9 packages with known vulnerabilities -
  `unbound-1.25.1`, `openssl-3.0.20,1`, `ldns-1.9.0`, `python313-3.13.13_1`, `openvpn-2.7.4`,
  `curl-8.20.0`, `openssh-portable-10.3.p1,1`, `strongswan-6.0.6`, `expat-2.8.1`. Whether a
  firmware update fixes them was not checked.

### Home Assistant T620 `192.168.20.13`

Unauthenticated HTTP only: `/` 200 on port 80, no TLS (443 and 8123 do not answer); `/api/` 401;
`/auth/providers`: only `homeassistant` (no `trusted_networks`); `/api/onboarding`: all steps done.
Headers `X-Frame-Options: SAMEORIGIN`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`.
Port 4357 serves "Home Assistant observer" without login. Version not checked.

### Switch `192.168.1.2`

Port scan only: TCP 80 open from LAN and IOT (HTTP login page); 22, 23, 443 filtered from IOT.

## Findings

Severity: high / medium / low / info. Status: `open`, `accepted`, `mitigated`, `fixed`, `n/a`.

### Re-status of S1-S15 (2026-09-10)

| ID | Finding | Prod evidence (2026-10-20) | Status |
|----|---------|----------------------------|--------|
| S1 | Postgres published on `0.0.0.0:5432` | `ss`: `0.0.0.0:5432 docker-proxy`; open from LAN and IOT; `compose/core/docker-compose.yml:21` `"5432:5432"` | **open**, high |
| S2 | Docker socket in containers | Portainer `rw`, Dozzle and Diun `ro` (`docker inspect`); Dozzle `authProvider":"none"` on `:8080`, open from LAN and IOT | **open**, high (Dozzle); Portainer accepted |
| S3 | Authelia not in front of the apps | no Authelia or proxy container on prod; 9091 closed; draft decision 0007 (proxy + Authelia) is in the working tree, not in `HEAD` | **open**, high |
| S4 | Authelia self-signed TLS | Authelia not running on prod | n/a on prod |
| S5 | Images on `:latest` | all running images tagged; omni-tools `latest@sha256` digest; two local builds | **fixed** (holds on prod) |
| S6 | Guest has no firewall | NAS and apps: `ufw` inactive, `INPUT` ACCEPT; Proxmox: `pve-firewall` disabled. Every port is open to LAN and IOT (S7 tables) | **open**, high |
| S7 | nmap from prod networks | this report: LAN, IOT, APP done; WG and WAN not | **done** for LAN/IOT/APP; WG/WAN open |
| S8 | Leftover credentials in `ansible/docker-containers.yml` | file still there with `PGADMIN_DEFAULT_PASSWORD: admin` (line 32), header marks it DEPRECATED, "delete after F9 close" | **open**, medium |
| S9 | OPNsense `config.xml` copies on the laptop | `opnsense/backups/` in the main checkout: 15 files (3 from 2026-07-01, 12 from 2026-10-19/20), all `0600`, gitignored (`.gitignore:12`), 0 tracked | **open**, medium - grew from 3 to 15 |
| S10 | Secrets on the guest; Bitwarden copy | `/opt/homelab/secrets` `root:root 0700`, files `0600`; `.env` `0640`; vault sync verified 2026-10-20 (`security.md`, operator) | **fixed** |
| S11 | Apps without accounts | Actual `"bootstrapped":false`, Trilium `"isInitialized":false` on prod: whoever opens them first from LAN, IOT or WG sets the password. Omni-tools, DumbWhois, BentoPDF: no auth by design | **open**, raised to high on prod |
| S12 | SSH on the apps guest | NAS and apps: `passwordauthentication no`, root locked, one key | **mitigated** |
| S13 | Zotify image runs as root | `compose/core/zotify/Dockerfile` has no `USER` | **closed** - Zotify removed in the same batch (2026-10-20); its volumes are left for the owner |
| S14 | CI deploy without F7 secrets | `Apps Deploy Prod` succeeded 2026-10-20 20:18 UTC (`gh run list --branch main`) | **fixed** |
| S15 | No image CVE scan | no Trivy in `.github/workflows/` or `utils/` | **accepted** |

### New findings

| ID | Severity | Finding | Evidence | Recommendation | Status |
|----|----------|---------|----------|----------------|--------|
| S16 | high | IOT reaches the router itself, the LAN and every app port. The IOT rule excludes only HOMEOFFICE and GUEST; the homelab servers share L2 with the Tuya devices | `pfctl -sr`: `pass in quick on vlan03 inet from (vlan03:network) to ! (NotForIOT:network)`; IOT scan: router 22/80/443/8443 on `.20.1`, `.1.1`, `.50.50`; laptop answers RST on 3000; all 21 app ports | Add IOT block rules above the pass: to the firewall's own addresses except DNS/DHCP/NTP and SSH from the NAS `.20.12` (OPNsense backup, `prod-target.md` section 6), to LAN, to APP except what HA needs. Longer term move Proxmox, NAS, HA and the runner off the IoT VLAN | open |
| S17 | high | Router SSH accepts root with a password (and keyboard-interactive) on every interface, reachable from LAN and IOT | `sshd_config`: `PermitRootLogin yes`, `PasswordAuthentication yes`; offered `publickey,password,keyboard-interactive`; root password set in `config.xml`; IOT scan 22 open on all router addresses | Password and keyboard-interactive login off, root key-only; SSH reachable from LAN and the NAS `.20.12` only. Root login itself stays: the NAS backup uses a root key with a forced command (`utils/f2-opnsense-backup-key.sh:2-3`). Setting in System > Settings > Administration (general knowledge, not verified here) | open |
| S18 | high | Proxmox root SSH with a password, no host firewall, no TFA on `root@pam`; SSH and GUI 8006 reachable from LAN and every IOT device | `sshd -T`: `permitrootlogin yes`, `passwordauthentication yes`; `pvesh get /access/tfa`: none; `pve-firewall`: disabled; 7 password logins in 7 days, all from the laptop | Turn TFA on for `root@pam`. Terraform passes `proxmox_ssh_password` (`terraform/providers.tf:8`, `infra-apply-prod.yml:49`); give it a key (`agent = true` already set) and then set `PasswordAuthentication no`, or allow passwords only in an sshd `Match Address` block (general knowledge, not verified here). Enable the PVE firewall for 22/8006/3128 from LAN, WG and the runner | open |
| S19 | medium | Terraform token has full Administrator | `homelab-prod@pam!terraform` `privsep=0`; ACL `/` `homelab-prod@pam` `Administrator` | Separate privileges: `privsep=1` and a role with the VM/storage privileges the provider needs | open |
| S20 | medium | The prod runner of a public repo holds the key to root on NAS and apps, sits on IOT and has open egress | `/home/runner/.ssh/homelab_prod_ed25519`; `sudo -n -l` on NAS/apps: `NOPASSWD: ALL`. Mitigations in place: fork approval `all_external_contributors`, `sha_pinning_required: true`, default token `read`, unprivileged CT, inbound drop, no sudo | Keep the mitigations. Narrow `ubuntu-prod` sudo to the commands the deploy runs if feasible; restrict CT 110 egress to GitHub, the NAS, apps and Proxmox | accepted risk until reviewed |
| S21 | medium | 9 router packages with known vulnerabilities | `pkg audit -q` on OPNsense 26.1.9 (vuln.xml 2026-10-18): unbound, openssl, ldns, python313, openvpn, curl, openssh-portable, strongswan, expat | Check for a newer 26.1.x firmware (System > Firmware; general knowledge, not verified here) and update in a maintenance window | open |
| S22 | low | NFS export with `no_root_squash` | `/etc/exports`: `/export 192.168.50.0/26(rw,...,no_root_squash,crossmnt)` | Keep the client range to `192.168.50.30/32`; use `root_squash` if no stream writes as root | open |
| S23 | low | Admin logins over plain HTTP: HA `:80`, AdGuard `:80`, switch `:80` | `curl`: HA 200 on 80, no 443/8123; AdGuard `302 /login.html`; switch `Redirect to Login` | HTTPS for HA (proxy of decision 0007 or HA's own cert); AdGuard UI on 8443 only; switch admin from LAN only | open |
| S24 | low | Listeners in no exposure table | Proxmox 111, 3128; HA 111, 4357 (observer, no login), 5355, 18555; router 53530 (unbound, bypasses AdGuard filtering), 853, 8443; NAS mountd/statd; apps 111 | Record the intended ones in `docs/network.md`; block 53530 from clients; firewall the rest with S6/S18 | open |
| S25 | low | Stale pf rule APP `.50.30` -> NAS TCP 22 still loaded | `pfctl -sr`: `pass in quick on vlan07 inet proto tcp from 192.168.50.30 to 192.168.20.12 port = ssh`; APP probe 22 open; `docs/network.md` marks it unused | Remove with the next router change, as planned | open |
| S26 | low | Pending security updates on NAS and apps | 4 each, `noble-security` (`ca-certificates`, `liblzma5`, `python3-jwt`, `xz-utils`); `unattended-upgrades` enabled | None if the next unattended run installs them; check again | open |
| S27 | info | X11 forwarding on | `sshd -T`: `x11forwarding yes` on Proxmox, NAS, apps | `X11Forwarding no` with the next SSH change | open |

## Not done

- **S7 from WireGuard:** the laptop has no WireGuard peer set up in this session; testing needs a peer
  config, which is a change outside read-only scope.
- **S7 from WAN:** no vantage point outside the home network; the ISP router in front of
  `192.168.100.2` decides what reaches OPNsense (`knowledge/networking.md`). Expected: TCP 443
  (HAProxy) and UDP 51820 only.
- **UDP 51820** from any network: WireGuard does not answer unauthenticated packets; no
  `open|filtered` result can confirm it.
- **Lynis** on `ubuntu-apps` / `ubuntu-nas`: not installed, and no install allowed.
- **Home Assistant authenticated checks** (users, MFA, version, add-ons, `HA_TOKEN` scope): no token.
- **OPNsense firmware update availability:** `opnsense-update -c` printed nothing; a read-only check
  was not established.
- **Router GUI accounts:** two users in `config.xml`, one with an OTP seed; which one lacks TOTP was
  not checked.
- **Laptop host firewall:** no root on the laptop to read why IOT gets drops on all ports but 3000.
- **gitleaks / Trivy re-run** and the switch configuration (no login).

No change outlives this audit: nothing was written on any host; scan output stayed in the session
scratch area on the laptop. The scans left normal log lines (sshd, pf, app access logs) on the hosts.
