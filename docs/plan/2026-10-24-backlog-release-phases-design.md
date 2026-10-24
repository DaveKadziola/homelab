# Backlog release phases - design

Status: draft for operator review (revision 2: operator review and critic review applied)
Date: 2026-10-24
Source of the backlog: frontmatter of [`greenfield-plan.md`](greenfield-plan.md) on `develop`
(commit 153a813).

## 1. Goal and constraints

Work through the open backlog from the least to the most invasive item with as few prod
releases (`develop` -> `main` PRs) as possible, each release as large as is safe.

Agreed with the operator on 2026-10-24:

- Scope is invasiveness levels 1-3 (section 2). Level 4 (rebuilds) stays in the backlog for its
  own design.
- When a read-only audit finds something to change, the fix becomes its own backlog item and is
  implemented in this plan (R1 if it only adds, R2 if it changes something that exists).
- Docker image updates are in scope (Diun reported newer tags).
- Two releases (approach 1 of three considered; one big release and three releases rejected).
- opnsense-wan-audit, including the scan from outside, runs in Phase 0 instead of last as
  recorded on 2026-10-22 (`greenfield-plan.md:72`), so that its fixes can land in R2 (operator,
  approval of the phase structure). No R1 or R2 item changes a WAN rule or port forward; if a
  Phase 0 fix tagged R2 does, the operator repeats the outside scan in the R2 window.
- Manual changes on prod hosts (Proxmox, Home Assistant, router) count as prod deployments and
  are done in the window of a release, not on their own. The agent makes them through the
  Remote Control session, only after the operator's explicit consent to that change. Each one
  follows `AGENTS.md` section 11: old value saved, smallest change, effect verified, restore
  command reported.
- Read-only prod work runs through a Remote Control session on the operator's laptop: the cloud
  workspace has no route to the home network.
- Every phase has reviewer and critic agents whose job is to find what passes on DEV and fails
  on prod (section 6).
- No phase may lose data, configuration, a database or a credential irreversibly (section 5).

Operator-only steps. The agent prepares the exact commands and waits; it never asks for,
prints or copies a secret (`AGENTS.md` section 11):

- unlocking Bitwarden (`bw login` / `bw unlock`, `knowledge/security.md:71-72`);
- preparing the clean machine for backup-decrypt-drill and putting `RCLONE_CONFIG` on it (the
  laptop holds `~/.homelab-secrets/prod/RCLONE_CONFIG`, so it is not clean);
- enrolling TFA for `root@pam` and the TFA login test;
- creating Cloudflare tokens and OpenRouter keys in the provider accounts, and pasting each with
  `utils/gen-app-credentials.sh --paste`;
- reading spend from accounts that have no credential in `~/.homelab-secrets` (ai-cost);
- editing rulesets, approving `prod-approve` / `prod-gate`, merging release PRs.

Once the operator has pasted a value, the agent places it on the host from the cache without
printing it.

Unchanged rules from `PROJECT-CONTEXT.md` section 3: the operator merges every release PR and
approves `prod-approve` / `prod-gate`; no direct push to `develop` or `main`; the router's live
configuration changes only with the operator's consent to that change; a plan that replaces
`ubuntu-apps` stops the release.

This changes `PROJECT-CONTEXT.md` section 6, where the prod and router rows say "no". Before
Phase 0 a docs PR into `develop` changes the prod row to "no, except manual changes on the
Proxmox host and Home Assistant inside a release window, made by the agent through the Remote
Control session after the operator's consent to each change (operator 2026-10-24);
`ubuntu-apps` and `ubuntu-nas` change only through the release deploy", and the router row to
"only inside a release window, through the Remote Control session, after the operator's consent
to each change (operator 2026-10-24)".

## 2. Invasiveness levels

| Level | Meaning | Items |
| --- | --- | --- |
| 1 | Read-only on prod; work on DEV and in the repo only | monitoring-audit, adguard-review, opnsense-wan-audit, syncthing-smb-check (one test file, section 3.1), backup-decrypt-drill, rebuild-data-safety, ai-cost (measuring), container-file-access (Portainer check), joplin-to-trilium (DEV test with synthetic notes), trilium-ai-access (design questions, section 3.5), app database survey (section 3.6), leftovers of the 2026-10-20 audit, image inventory |
| 2 | Adds to prod; nothing existing changes meaning | CI and test fixes found by the critic review (section 3.2), weekly-security-audit, ai-log-analysis (sending off), monitoring gap fixes, image updates the store check clears (section 3.1), container-file-access (drive-mapping script; file browser or SFTP only if the Portainer check shows a gap), homarr-dashboard-widgets, postgres-init list cleanup, ai-cost follow-up, `utils/ha.py` TLS support, trilium-ai-access if its design only adds |
| 3 | Changes or removes something on prod | pve-hardening, admin-certs, DROP DATABASE / DROP ROLE, app moves to Postgres, db-admin-tool (CloudBeaver replaces pgAdmin, only under the condition in section 3.6), public-map-split, image updates that change the app's store or whose migration status is unknown, Immich Postgres 14, ai-log-analysis sending on, trilium-ai-access changes to existing tokens, audit fixes that change config; then git-history-state |
| 4 | Rebuilds - out of scope | ubuntu-2604, disk-encryption, subnet-refactor, home-assistant-zigbee |

`security-audit-fixes` closes when pve-hardening and admin-certs close (`greenfield-plan.md:6`)
and the items Phase 0 step 8 creates are closed or accepted by the operator.
`security-public-repo` closes when public-map-split and then git-history-state close
(`greenfield-plan.md:18`).

Shared Postgres databases and their roles are created by the hard-coded `postgres-init` loop in
`compose/core/docker-compose.yml:45-50` on every deploy. Line 48 creates a login role of the same
name with `POSTGRES_PASSWORD`. `ansible/playbooks/deploy-core.yml:605-620` also creates `easytodo`
with its own password. `homelab` is `POSTGRES_DB` (`compose/core/docker-compose.yml:16`).
`databases:` in `config/services.yml:59` is documentation that no code reads. Removing a name from
the loop deletes nothing on prod, so the list cleanup is level 2; DROP DATABASE and DROP ROLE are
level 3.

## 3. Phases

### 3.1 Phase 0 - read-only, no deploy

One Remote Control session on the laptop. Reads on prod run one after another, never in
parallel (`AGENTS.md` section 6). At the start the operator names the non-public place for raw
results (for example a folder on the NAS, where the weekly audit reports go,
`greenfield-plan.md:24`).

1. Image inventory, per image:
   - every place its version is set: `compose/` for most images; Immich in
     `ansible/playbooks/deploy-core.yml:322` (written to `.env`, overrides the compose default at
     `compose/core/docker-compose.yml:265,292`) and `compose/core/.env.example:15`; Caddy in
     `compose/core/caddy/Dockerfile`, `compose/core/docker-compose.yml:148` and `caddy_image` in
     `deploy-core.yml:24` (all three change together);
   - the image digest running on DEV and on prod (`docker image inspect`, read-only). The deploy
     never pulls (`deploy-core.yml:575-577`), so the floating tags `postgres:16-alpine`
     (`compose/core/docker-compose.yml:12,36`), `valkey:8-alpine` (`:332`) and Immich's
     `14-vectorchord...` (`:343`) keep whatever was pulled first; for them the version the
     container reports is recorded;
   - the Beszel agents outside compose (prod-nas, prod-pve, prod-router, the prod-hass add-on,
     `knowledge/apps/beszel.md:13`) and whether a hub update needs an agent update;
   - the newest stable tag and the bump type. A first unverified web lookup (2026-10-24) found
     patch updates for Syncthing, Portainer, Immich, Dozzle, Postgres 16 and Valkey 8, minor for
     Jellyfin and Homarr, an unclear state for Beszel and caddy-dns/cloudflare, and PostgreSQL 14
     in the Immich database image reaching end of life on 2026-11-12;
   - the store check, on DEV, for every app that keeps state: record the store before the new
     image starts and after it is healthy. Postgres stores: `pg_dump --schema-only` and the app's
     migrations table. SQLite stores (Homarr `db.sqlite`, Jellyfin, Beszel, Navidrome): schema and
     migrations table read with python3 `sqlite3`. A store that cannot be compared this way (for
     example Portainer's `portainer.db`) counts as changed. A difference or an unknown makes the
     update level 3 (R2). Release notes alone do not clear an update.
2. backup-decrypt-drill, on the clean machine the operator prepared (section 1): list
   `pcloud-crypt:homelab-backups` and check that every stream in `offsite.include` (postgres,
   volumes, homeassistant, repo-zip; `config/storage.yml:126-129`) is there. Copy one Postgres dump
   and the newest `homeassistant/ha-full-*.tar`. Restore the dump into a throwaway database on DEV
   (`utils/backup/restore-pg.sh --env dev --db scratch --create`). Prove that the HA tar opens with
   the prod `HA_BACKUP_PASSWORD`, entered by the operator, without restoring it onto the DEV HAOS
   twin (that would bring prod integrations and tokens to DEV, `AGENTS.md` section 1.4); the
   method is chosen in Phase 0. The copies and the scratch database are removed afterwards, after
   the operator says yes. `knowledge/backup.md` gets the encryption inventory: pCloud by the crypt
   passwords in `RCLONE_CONFIG`, HA tars by `HA_BACKUP_PASSWORD`, the shared NAS streams and
   NAS-private (router config, HA YAML, VM dumps) plain; the read-back steps for each; the pCloud
   size and the age of `.offsite-ok` on prod.
3. rebuild-data-safety:
   - what no backup holds, with size and file count: Samba `share` (`/srv/purple/share`),
     `media/sync`, `media/vsum`, the SA500 media libraries (`knowledge/rebuild.md:129-131`). The
     NAS disks are attached with `backup=0` (`utils/pve-attach-nas-disks.sh:75`), so the VM dumps
     do not hold them either. For each, the containers that mount it read-write on prod (known:
     Immich `media/immich`, Jellyfin `media/video`, Syncthing `media/sync`;
     `compose/core/docker-compose.nfs.yml:9,22,27`) and where a copy exists outside the homelab
     (the separate pCloud media copy, `knowledge/backup.md:26`; the phone for `media/sync`);
   - every named volume and stateful bind mount in `compose/core/docker-compose.yml` and
     `docker-compose.nfs.yml` compared with `utils/backup/volumes.sh:14-21`. Today jellyfin_config,
     navidrome_data, beszel_data, beszel_agent_data, pgadmin_data, caddy_data, caddy_config and
     diun_data are only in the nightly VM 101 dump: not offsite, and only a whole-VM restore is
     documented. Whether each joins `volumes.sh` (an R1 item) is decided at the Phase 0 review;
   - which tarred volumes hold SQLite or BoltDB files: `volumes.sh` tars them while the apps run
     (`utils/backup/volumes.sh:24-30`);
   - what a prod rebuild needs by hand;
   - the volume-tar restore on DEV from DEV's own tars, never from prod tars (section 5). The
     2026-10-19 drills did not exercise it (`knowledge/rebuild-drill-2026-10-19.md:46`,
     `knowledge/rebuild-drill-2026-10-19b.md:36`). The commands used replace the one-line comment
     in `knowledge/rebuild.md:122`, so the release gate repeats a written procedure; a failure
     becomes an R1 item;
   - free space on `ubuntu-apps-dev` (`df`, `docker system df`) and in the nested pool
     (`lvs pve/data`) against the size of the newest prod dumps, for the gate in section 5.
4. monitoring-audit: the failure list (`greenfield-plan.md:21`) against Uptime Kuma, Beszel, Diun,
   Trivy, the apt and NIC mails and the backup freshness check. Known gaps: no update report for
   OPNsense or Home Assistant; no scheduled certificate-expiry check by name (the `proxmox`
   monitor checks the IP with `ignore_tls`, `config/monitoring.yml:58`); no workflow syncs Kuma
   monitors (`knowledge/monitoring.md:26-28`).
5. syncthing-smb-check: the operator puts one test file on the phone, which syncs it to prod
   `media/sync`; the agent checks it over the Samba share `media`, folder `sync`, and the file
   ownership between the container and the Samba force user. Deleting the test file afterwards is
   asked.
6. adguard-review (read only), ai-cost measurement (spend and limit per key; reading account
   spend is the operator's step), and opnsense-wan-audit with S7 from WAN and WireGuard: the rule
   read compared with `docs/network.md`; the operator puts the laptop on a phone hotspot and scans
   the WAN address once with WireGuard down and once through the laptop's existing Admins peer
   (assumption, checked first: the laptop still has that peer). A scan as a non-Admins peer needs
   a temporary peer, which is a router change: asked for, done in the R1 window, removed after.
7. Repo and DEV only:
   - Portainer file-access check (what it already gives for Docker volumes);
   - Joplin -> Trilium export test on DEV with a synthetic Joplin export made for the test
     (nested notebooks, tags, an image, an attachment, a code block, a to-do), never the operator's
     notebooks; the steps go to `knowledge/apps/trilium.md`;
   - the trilium-ai-access questions (section 3.5);
   - the app database survey (section 3.6).
8. Leftovers of the 2026-10-20 audit (`knowledge/security-audit-2026-10-20.md:243,248-264`):
   - HA listeners 111, 4357, 5355, 18555: which are reachable from LAN and IOT (HA `.20.13` is not
     in `HomelabServers`, `utils/opnsense-lockdown-remote.sh:166`);
   - HA authenticated checks with the prod `HA_TOKEN`: users, MFA, version, add-ons;
   - which router GUI user has no TOTP, read from the newest NAS copy of `config.xml`;
   - the switch configuration, read with the operator logged in.
   Lynis is not run: it needs an install on prod. It becomes a candidate R1 item for the operator
   to accept or drop.

Output: one document per audit in `knowledge/` with the method, the conclusions and example
addresses (RFC 5737), following `knowledge/README.md`: no personal data, no full logs. The repo
is public (`PROJECT-CONTEXT.md` section 3) and the house map is leaving it
(`greenfield-plan.md:66`), so raw results stay off it: real and WAN addresses, the domain,
AdGuard client names, domains and query-log extracts, scan output and OPNsense rule exports go to
the non-public place named at the start. Each finding that needs a change becomes a backlog item
tagged R1 or R2.

Phase 0 ends with an operator review: the finding list, the R1/R2 tags, and the decisions in
section 9. A finding that needs level 4 work goes to the backlog, not into R1 or R2.

### 3.2 Release 1 - additions

One PR per item into `develop`, in this order:

1. CI and test fixes found by the critic review. They only add checks and change nothing a prod
   service does:
   - deploy gate: add every source path that the deploy uses (`deploy-core.yml:405-411`,
     `deploy-storage.yml:678-679,769`, `apps-deploy-dev.yml:87`) to the regex at
     `apps-deploy-dev.yml:41`, and the same change to `tests-dev.yml:49`, which must stay
     identical. GitHub reads `apps-deploy-dev.yml` from `main`, so until R1 is on `main` every item
     PR needs the manual dispatch in section 4;
   - prod NFS render: CI Validate also renders the prod file set (base plus
     `docker-compose.nfs.yml`, prod profiles from `config/services.yml`) with the existing
     placeholders (today only the base file, `ci-validate.yml:54`);
   - prod-tests-skip: `HL_SKIP_WHEN_UNREACHABLE: "0"` in the `post-deploy-tests` job of
     `apps-deploy-prod.yml`, and the stale comment at `utils/run-tests.sh:105` corrected (prod has
     run since F3). In the same PR `tests/infra/run.sh:162-167` reports SKIP for `terraform/plan`
     on prod in every case (Infra Plan Prod covers it). For `infra/ansible/check` the PR either
     gives the test step the same environment as the step "Deploy compose/core"
     (`apps-deploy-prod.yml:84-118`, plus `GROCERY_SECRET_KEY` in `tests/infra/run.sh:193`) or
     keeps it SKIP and records it in `tests/README.md` as a known prod gap. This cannot be proved
     on DEV: the first prod run after the release is read in full, and a new FAIL there blocks
     the tag (fix forward or revert).
2. Image updates the store check cleared, patch first. `postgres:16-alpine` and `valkey:8-alpine`
   have no tag to bump; if the operator chooses to pin them (section 9), the PR pins the exact tag
   DEV tested, updates `knowledge/apps/diun.md:11`, and either makes Diun report the new tags (its
   `includeTags` in `compose/core/diun/diun.yml:14` does not match `-alpine` tags) or records
   where their updates are seen instead. An update of a host agent (Beszel on prod-nas, prod-pve,
   prod-router) is a manual prod change in the release window, with consent per host.
3. postgres-init list cleanup: one PR removes the names the survey (section 3.6) confirmed unused
   from the loop at `compose/core/docker-compose.yml:45`, from `config/services.yml:59`,
   `knowledge/apps/postgres.md:9`, `knowledge/prod-target.md:55` and `used_by` in
   `config/identities.yml:173`. It keeps the entries of every app the survey may move to Postgres
   in R2 and never touches `homelab`.
4. Monitoring gap fixes from Phase 0 (known: update reports for OPNsense and Home Assistant, a
   certificate-expiry check by name that alerts under 14 days, the threshold of
   `tests/net/run.sh:136`). A change to `config/monitoring.yml` reaches Kuma only through
   `utils/kuma-sync.py`, run by hand: `--env dev` before the DEV tests; on prod `--env prod
   --dry-run` and then `--env prod` from the laptop session in the R1 window, as a manual change
   with consent, with the dry-run output in the release PR.
5. weekly-security-audit (own brainstorming first). Reports by mail and on the NAS, never in a
   public-repo artefact; the repo is public, so this includes CI logs (`knowledge/security.md:37`).
   Its nmap starts from the 2026-10-20 method: the homelab hosts only, never a whole /24, because
   IOT holds Tuya devices (`knowledge/security-audit-2026-10-20.md:9-10`).
6. ai-log-analysis (own brainstorming first), with sending to OpenRouter off on prod (dry-run): it
   writes the cleaned payload to the NAS next to the weekly audit report. It sends only
   allowlisted, aggregated fields, never raw log lines or raw audit output, and writes nothing raw
   to the repo (`greenfield-plan.md:15`); its brainstorming lists the allowlist for the operator to
   approve. Before the PR merges, the operator creates a regular OpenRouter key for it per
   environment with a credit limit set from the ai-cost measurement, as for `vsum-homelab-prod`
   (`docs/secrets-inventory.md:122`); it does not reuse `VSUM_OPENROUTER_KEY`. It gets no Trilium
   credential (section 3.5).
7. ai-cost follow-up: any cheaper model or token reduction the measurement supports for vsum or
   ai-log-analysis becomes its own item (R1 if it only changes a model or prompt setting, R2 if it
   changes an existing prod app's behaviour). Key limits are set by the operator in OpenRouter and
   need no deploy.
8. container-file-access (own brainstorming first, starting from the Phase 0 Portainer result):
   the laptop script that maps the drives (the Samba shares, plus container-file access if one is
   added); a file browser or SFTP for the Docker volumes only if the Portainer check shows a gap,
   read-only by default. `media/sync` and the media libraries are mounted read-only; no write
   access to a tree no backup holds.
9. `utils/ha.py` TLS support: the REST and websocket clients take the scheme from `ha_url`
   (`http`/`ws` or `https`/`wss`) and verify the certificate. While prod `ha_url` stays `http`
   this changes nothing on prod; it shrinks the admin-certs window in R2.
10. Homarr widgets, only if the Homarr update they need was cleared by the store check; otherwise
    they follow it into R2.
11. Phase 0 fixes tagged R1, and trilium-ai-access if its design only adds (section 3.5).

Router and host steps in the R1 window, each a separate change with the operator's consent:

- an AdGuard rewrite for each prod name R1 adds (the names in
  `utils/gen-proxy-config.py --env prod --file adguard` on `develop` that are not in that list on
  `main`): `utils/adguard-rewrites.sh --dry-run` first, then the real run with its auto-revert. The
  smoke tests reach names with `curl --resolve` (`tests/smoke/run.sh:180`), so the release
  checklist has `dig <name> @<router>` for each new name;
- router access for the OPNsense update report if it needs more than the NAS backup key, which may
  only run `cat /conf/config.xml` (`utils/opnsense-backup-key.sh:2-3`); the method is chosen in
  that item's brainstorming and installed with a dry-run and an auto-revert;
- the Kuma sync of item 4, Beszel agent updates of item 2, and any Phase 0 fix tagged R1 that
  changes the router or a prod host, listed before the release PR is opened.

R1 adds no real address, domain or client name to `docs/` or `knowledge/`. Code takes addresses
from the existing sources (`config/*.yml`, the Ansible inventories) and adds no new literals, so
public-map-split has nothing new to move.

After R1, once the vsum token decision in section 3.5 is in effect, the operator can import the
Joplin notes into prod Trilium by hand (it only adds data).

### 3.3 Release 2 - changes to existing prod

R2 PRs merge into `develop` only after the operator confirms R1 on prod (section 5). From the
first R2 merge, `develop` carries changes that need the R2 window, so nothing is released from
`develop` until R2 is complete. A prod fix that cannot wait is a separate release and the
operator's decision each time: a PR into `main` from a branch cut from `main` (as #103 and #147
did), holding only the fix, with the PR reviewer, the parity critic and section 5 step 1. It is
not deployed on DEV first (Apps Deploy Dev runs only for `develop`), so the PR lists the fix as a
prod check. Afterwards `main` is merged back into `develop` through a PR with a real merge commit,
never a squash (6a581b1, 4b02915).

One PR per item into `develop`, in this order:

1. trilium-ai-access changes to existing tokens or apps, starting with `VSUM_TRILIUM_TOKEN`,
   unless it was already revoked in the R1 window (section 3.5).
2. public-map-split (own brainstorming first; it changes where the deploy reads addresses).
3. Immich Postgres 14 (placed early so its DEV rehearsal runs first; the prod date is the R2
   window either way). Only with an upstream migration path. PostgreSQL 14 reaches end of life on
   2026-11-12 (date confirmed in Phase 0 step 1), before R2 can ship, so Immich's database runs
   unpatched from then until R2. It publishes no port, but every service on the core compose
   default network can reach it (`compose/core/docker-compose.yml:342-363`). The Phase 0 review
   decides whether that is accepted until R2. Without an upstream path the item goes back to the
   operator as a decision (accept the risk with a review date, or plan a separate migration); it
   does not return to the backlog on its own. Procedure in section 5.
4. admin-certs (own brainstorming first):
   - Proxmox: PVE ACME DNS-01 with its own Cloudflare token (Zone.DNS edit on the zone only),
     created by the operator and held by the device; its name and storage place go into
     `config/identities.yml`. Nothing in the repo depends on the PVE certificate
     (`terraform/providers.tf:3`, `insecure = true`).
   - Home Assistant: the same with a second token. One PR sets prod `ha_url` in
     `config/storage.yml` to `https://hass.dkhomelabserver.xyz` (the certificate's name, not the
     IP) and changes the Homarr link (`utils/gen-homarr-board.sh:136`); `utils/ha.py` already
     speaks TLS from R1 item 9. Everything that calls the HA API reads `ha_url`: the full HA backup
     (`ha-pull.sh` -> `ha.py backup`), the prod deploy step `ha.py bootstrap` / `deploy`
     (`apps-deploy-prod.yml:127-133`) and the `ha` suite.
   - The switch stays on HTTP, from Admins only. It is on the LAN subnet, where the router does not
     filter (`docs/network.md:66`); the brainstorming states how that is enforced, and if the
     switch cannot enforce it, the operator decides.
   - Before the window: check how the PVE and HA ACME clients confirm the TXT record given the
     AdGuard redirect on IOT (`docs/network.md:91`; that redirect once broke Caddy's DNS-01,
     `knowledge/troubleshooting.md:69`), and that `hass.dkhomelabserver.xyz` resolves from the
     prod runner and the NAS.
   - DEV has no Cloudflare token and no ACME on the nested PVE or the HAOS twin, so issuance and
     renewal are prod checks in the release PR. DEV tests the TLS client against a local CA on the
     twin.
5. pve-hardening (`greenfield-plan.md:9`). DEV first:
   - a role on the nested PVE with the privileges the bpg provider uses plus what
     `utils/pve-backup-job.py` needs (Datastore.Allocate, Sys.Modify; `apps-deploy-prod.yml:72-74`,
     same token); a `privsep=1` token with that role on `/`; DEV's `PROXMOX_API_TOKEN_ID` and
     `PROXMOX_API_TOKEN_SECRET` set to it;
   - the provider PR gives Terraform the SSH key and removes `password` from
     `terraform/providers.tf`, and updates `docs/f3-proxmox.md:144-149`, `knowledge/rebuild.md:45`
     and the Proxmox line of section 6;
   - proof on DEV: an apply that creates a VM and its snippet over SSH (the drill of
     `knowledge/rebuild-drill-2026-10-19b.md`), then Apps Deploy Dev with the 'Proxmox backup job'
     step showing ok.
   Prod window, each host step with the operator's consent:
   - (a) TFA on `root@pam` (enrolled by the operator), console at hand;
   - (b) the runner key authorised for root, proved from the runner with a key-only SSH
     (`-o BatchMode=yes -o PasswordAuthentication=no`), plus a login test by the operator from a
     second session;
   - (c) the role created with the same command as on DEV and its privilege list compared; the
     new token created; the old prod `PROXMOX_API_TOKEN_ID` and secret copied into a separate
     Bitwarden note (not into `~/.homelab-secrets/prod/`, which `sync-secrets-to-github.py --apply`
     pushes); the operator swaps both values in environment `prod`;
   - (d) the release merged; the refreshed plan of Infra Apply Prod passes with the new token; the
     'Proxmox backup job' step's own outcome is success (the step has `continue-on-error`);
   - (e) `PasswordAuthentication no` and `X11Forwarding no` (S18, S27), then the key-only SSH
     repeated from the runner and from an Admins host;
   - (f) PVE firewall: 22 and 8006 from Admins and the runner 192.168.20.14, replacing the default
     management set, plus the Kuma option the operator chose (section 9). Before
     `pve-firewall start` the session confirms its own source address (`$SSH_CLIENT`) is in Admins;
     the laptop on IOT Wi-Fi is not. Then the runner SSH and a manually started Infra Apply Prod
     run are repeated. Beszel needs no inbound rule: the agent dials the hub
     (`knowledge/apps/beszel.md:13`);
   - (g) the old token and its Bitwarden note deleted only after (d) to (f) pass and the next
     04:30 dump made `storage/backup/fresh-vzdump` PASS with `pvesm status` showing `nas-backups`
     active; `PROXMOX_SSH_PASSWORD` removed only after (e) passes. Each deletion is asked.
   Restore commands: `pve-firewall stop`; sshd config back from the saved copy; the old token
   values back in environment `prod` until (g).
6. App moves to Postgres that the survey in section 3.6 allows (data migration, DEV first), then
   DROP DATABASE and DROP ROLE of the names R1 removed from the loop. CloudBeaver replaces pgAdmin
   only under the condition in section 3.6.
7. Image updates the store check did not clear (changed store or unknown status).
8. ai-log-analysis sending turned on, after the operator has reviewed the cleaned payload of at
   least one real weekly run on prod.
9. Phase 0 fixes tagged R2.

### 3.4 After R2 - history rewrite, prod run rejected

git-history-state removes `terraform/terraform.tfstate`, `terraform/terraform.tfstate.backup` and
the house-map files listed by public-map-split from every ref on origin. Today 18dd8c6 is
reachable from all branches, all 7 tags (v1.0.0 to v2.4.1) and the `refs/pull/*/head` refs, so
rewriting only `main` and `develop` would leave the data public. Every step below is asked on its
own, because none can be undone:

1. Before: the only branches left on origin are `main` and `develop`, and no PR is open. Every
   other branch (today `docs/prod-plan-lessons` with PR #204, `feat/vsum`, this plan's
   `claude/...` branch) is merged or, with consent, deleted. A full copy of the old repository:
   `git clone --mirror` and `git bundle create <name>.bundle --all`, checked with
   `git bundle verify`, stored on the NAS outside any shared path and never pushed anywhere. The
   operator saves both rulesets (`gh api repos/<owner>/homelab/rulesets/25494696` and
   `/25494699`) as JSON next to it.
2. Install git-filter-repo (not installed): package, version and source named first.
3. Rewrite on a fresh mirror clone: all branches and all tags. Tags are rewritten and re-pushed
   under the same names (decision 0009 makes them the rollback points, and
   `utils/release-notes.py` uses the newest tag as the base of the next notes); the new tag SHAs
   go into `knowledge/`. The commit map is kept next to the copy. Stop if any check fails: the new
   `main` and `develop` tips have the same tree as the old ones; `git log --all -- <the removed
   paths>` prints nothing; no house-map address appears in any commit.
4. Push: the operator sets both rulesets to `enforcement: disabled` (`pull_request`,
   `non_fast_forward` and, on `develop`, `required_status_checks` all refuse a direct push). The
   agent force-pushes tags first, then `main` and `develop`. The push to `main` starts Infra Apply
   Prod; the operator rejects its `prod-approve`, so Apps Deploy Prod and its release job do not
   run. The push to `develop` starts the DEV runs; the tree is unchanged, so the plan must show no
   change. The operator restores both rulesets right after, and `gh api` output must match the
   saved JSON.
5. After: `git ls-remote origin` shows only rewritten refs; every local clone and runner checkout
   is re-cloned. Old objects stay reachable through `refs/pull/*/head` and GitHub's cache until
   GitHub Support purges them (general knowledge, not verified here; `greenfield-plan.md:69`); the
   request text is shown to the operator before it is sent.

### 3.5 trilium-ai-access - requirement

Operator 2026-10-24: AI may read only the Trilium notes and knowledge-base content the operator
marks as fit for cloud processing. Private notes never leave the home network, neither to
OpenRouter nor to any other cloud model. "Cannot read" means the AI path has no credential or
copy that reaches them; a prompt rule or a filter applied after the read does not count.

Scope. This bar applies to the AI tools this plan deploys or changes (trilium-ai-access, vsum,
ai-log-analysis). The coding agent that runs the phases is also a cloud model with shell access
to DEV and prod through the Remote Control session (the laptop user's prod key has
`sudo NOPASSWD: ALL` on `ubuntu-apps`, `docs/secrets-inventory.md:49`). For the agent the rule is
a procedure, not a credential boundary, which does not meet the bar above; the operator accepts or
rejects that in section 9. The procedure: the agent never opens, prints or queries note content
from Trilium on DEV or prod (not the UI, not ETAPI, not `document.db`, not an extracted
`trilium_data` tar). No copy of prod Trilium data is made on DEV or on any other host the agent
works on. A check of a Trilium backup prints only counts, sizes, checksums and
`PRAGMA integrity_check`.

What exists on prod: profile `vsum` is on (`config/services.yml:31`). A prod ETAPI token
`VSUM_TRILIUM_TOKEN` is set (`docs/secrets-inventory.md:125`) and answered 200 (commit 8db96c2).
`deploy-core.yml:328-330` writes it into the same `.env` as the OpenRouter key, and both reach
vsum-web and vsum-worker (`compose/core/docker-compose.yml:437-439`), which also fetch untrusted
feeds and pages (`:51`). Assumption, to verify in Phase 0: an ETAPI token is not limited to a
subtree, so any holder can read every note. If so, the rule is broken today.

Phase 0 answers, on DEV with test notes only:

1. Can an ETAPI token be limited to a subtree or a label? Checked in the Trilium source and
   documentation for the deployed version (the same on DEV and prod,
   `compose/core/docker-compose.yml:104`) and by a test on DEV.
2. How the operator marks a note as allowed (a label on a subtree root, a separate subtree), and
   how a new private note stays private by default.
3. If tokens are not scoped: candidate designs, for example a small local service that holds the
   ETAPI token and exposes only the marked subtree, or an export of the marked subtree into a
   separate store that the AI tools read. The service must not run on a cloud host.
4. Whether vsum reads any note at all (from the upstream code), and whether its token reaches
   more than vsum needs.
5. Where the "knowledge base" content lives, if it is not Trilium, and the same rule for it.
6. Local model vs OpenRouter for the content that is allowed.
7. On prod, read-only: the list of ETAPI token names in Trilium (Options -> ETAPI), to find every
   holder.

If question 1 shows tokens cannot be limited, the operator chooses (section 9):
(a) the agent revokes the prod vsum token in prod Trilium in the R1 window, with consent. vsum's
note export stops (`knowledge/apps/vsum.md:14`); no data is lost. Removing the GitHub secret alone
does not cut access (the deploy falls back to the runner cache, `deploy-core.yml:126-127`, and the
token stays valid). Before revoking on prod, check on DEV how vsum behaves with a set but revoked
token; the secret is emptied in the R1 deploy. Restore: create a new token and run
`./utils/gen-app-credentials.sh --env prod --secret VSUM_TRILIUM_TOKEN --paste --rotate`.
(b) the operator accepts the exposure until R2 item 1, recorded as a dated risk in
`knowledge/apps/vsum.md`.

The design gets its own short brainstorming. It lands in R1 if it only adds (a new service, a new
token) and in R2 item 1 if it changes an existing token or app. Until it lands, no AI tool gets a
new Trilium credential and no existing one gets wider. Private notes are imported from Joplin only
once no AI-path credential reaches them.

### 3.6 App databases and the admin tool

Operator 2026-10-24: CloudBeaver replaces pgAdmin only if some app database cannot be moved or
switched to Postgres and the operator needs access to it; otherwise pgAdmin stays and CloudBeaver
is not added.

Phase 0 survey:

- per app that keeps its own database file instead of the shared Postgres: the engine and file
  location, whether the upstream version in use supports Postgres, the migration path upstream
  documents, and the data at stake. Outcome per app: move to Postgres (R2, DEV first, dump of the
  old file kept), or stays outside Postgres;
- read-only on prod: `pg_database` and `pg_roles` compared with the loop at
  `compose/core/docker-compose.yml:45`, to confirm which entries nothing uses before the R1
  cleanup. Each database or role outside the loop (known: `todo_grocery` / `prod_todo_grocery`,
  `knowledge/apps/grocery.md:33`) goes to the operator to keep or drop; nothing outside the loop is
  dropped without that decision. `homelab` (superuser default database, healthcheck,
  postgres-init and pgAdmin maintenance database; `compose/core/docker-compose.yml:16,27,46`,
  `compose/core/pgadmin/servers.json:8`) is never a candidate.

If at least one app stays outside Postgres and the operator wants access to it, db-admin-tool
goes into R2: CloudBeaver replaces pgAdmin. The design names how CloudBeaver reaches each file (a
read-only mount of that app's volume, or a copy from a backup) and checks on DEV that a running
app's file is opened read-only. If CloudBeaver can reach Trilium's database, its login counts as
a Trilium credential under section 3.5: no AI tool gets it.

## 4. Release mechanics

Every item reaches `develop` through a PR that merges itself after `validate` and `plan`
(`PROJECT-CONTEXT.md` section 5).

- Apps Deploy Dev deploys and runs the post-deploy tests only when the merge changes a path that
  the gate at `apps-deploy-dev.yml:41` on `main` matches; Tests Dev runs only for `tests/**`,
  `utils/run-tests.sh` and `tests-dev.yml`. For each item the parity critic records the Apps
  Deploy Dev run whose post-deploy-tests passed for the item's merge SHA. If the gate did not
  match, `gh workflow run apps-deploy-dev.yml --ref develop -f sha=<merge sha>` runs before the
  next item starts.
- A PR that changes `.github/workflows/apps-deploy-*.yml`, adds a deploy path, or adds a secret
  name is checked on DEV by that manual dispatch, shows that each new secret has a line in
  `apps-deploy-prod.yml` and is set in environment `prod` (`gh secret list --env prod`), and is
  listed in the release PR as a prod check.
- After section 5 steps 1-2 pass, the release PR `develop` -> `main` is opened as a draft.
  Infra Plan Prod runs only on PRs into `main` (`infra-plan.yml:6-8`). The PR is marked ready for
  the operator only when step 4 holds and the parity and release critics have no open finding
  other than the prod checks listed in the PR. Step 3 runs in the release window, before the
  operator merges.
- Rollback of an R1 or R2 item on prod is a revert PR into `develop` and another release PR,
  which the operator merges and approves. It costs a release outside the two planned ones.

## 5. Data safety

Trees without a homelab backup (`share`, `media/sync`, `media/vsum`, the SA500 media libraries)
are not covered by the steps below. Before R1, because every prod deploy re-runs
`deploy-storage.yml` (`apps-deploy-prod.yml:68`), the operator decides per tree (section 9):
either a one-off copy on another disk or machine (target chosen by the operator; file count and
size compared at source and copy) kept until the release is verified, or acceptance of the loss
risk as decision 0002 does for `share`. Until that decision is carried out, no item updates an
image that mounts the tree read-write (Immich, Jellyfin, Syncthing), changes its path, mount,
ownership or Samba definition, or gives a new tool write access to it. Before and after each
deploy that touches such a tree, a file listing (path, size, mtime) is compared; it only detects a
loss.

Before every release:

1. Bitwarden holds every prod secret: with the vault unlocked by the operator,
   `utils/bw-store.py --pending` exits 0, and `utils/bw-store.py --env prod --dry-run` and
   `--env prod-plan --dry-run` list every note as `unchanged`. A generator exits 0 even when the
   vault is locked and leaves the value only in the cache and in GitHub (`utils/bw-store.py:17-20`).
2. Restore gate on DEV. Freeze `develop` first: auto-merge off on every open PR, no merge from the
   start of the gate until the release PR is merged; any merge repeats the gate. Dispatch Apps
   Deploy Dev for the `develop` tip and wait for its post-deploy-tests. Take a fresh prod backup
   (`homelab-backup` on apps, `homelab-nas-backup` on the NAS). Check free space on
   `ubuntu-apps-dev` and `lvs pve/data`; if the artefacts do not fit, stop and ask. Copy the prod
   Postgres dumps to a new scratch directory on the DEV apps guest outside `/mnt/homelab/backups`
   (DEV retention keeps the newest files per prefix, `knowledge/backup.md:24`) and restore each
   into a scratch database:
   - shared Postgres: `utils/backup/restore-pg.sh --env dev --db <name>_check --file <dump> --create`;
   - Immich: the same plus `--container homelab-core-immich-postgres-1 --user postgres
     --password-secret IMMICH_DB_PASSWORD`.
   The restore is proved by the row count of every table equal to the count in the dump, as in
   `knowledge/rebuild-drill-2026-10-19b.md:23`. The checks read only counts, never row contents.
   Prod volume tars are not restored on DEV: `trilium_data` holds every private note,
   `syncthing_data` the prod device identity, `portainer_data` the prod grocery stack secrets
   (`utils/bootstrap/portainer.sh:136-160`), and `homarr_data` is encrypted with the prod
   `HOMARR_SECRET_KEY`. They are checked on the NAS by a committed read-only Python script, run by
   the agent with consent (or by the operator, section 9): it lists each tar, extracts its SQLite
   files into a temporary directory that it removes, and prints only file counts, sizes and
   `PRAGMA integrity_check`. The procedure of restoring a volume tar is proved on DEV with DEV's
   own tars (Phase 0 step 3). Then `utils/run-tests.sh --env dev --suite all` as the DEV health
   check; it does not prove the restore (`utils/run-tests.sh:16,30`). Afterwards the `_check`
   databases and the scratch directory, both created by this gate, are removed. The release PR
   names the `develop` SHA and both results. This gate proves the procedure on the set taken at
   the gate; the set from step 3 is the rollback copy.
3. Release-window backup, before the operator merges the release PR:
   - run `homelab-nas-backup` on the NAS, check that the Proxmox job `homelab-vms` produced that
     day's 04:30 dump (`check-fresh.py` shows the vzdump stream; it is the only copy of the
     volumes outside `volumes.sh`), then `homelab-backup` on apps. For the volume tars, the apps
     whose volume holds an embedded database (Homarr `db.sqlite`; Trilium, Actual and Portainer as
     Phase 0 confirms) are stopped while `volumes.sh` runs and started after, each checked to
     answer; this is a prod service change with consent;
   - copy this run's files into `pre-release-<release>/` inside each shared stream folder
     (`postgres/`, `volumes/`, `homeassistant/`, `repo-zip/`): `hl_prune` and `ha.py backup` delete
     only files directly in the stream folder (`utils/backup/lib.sh:63-66`, `utils/ha.py:507-509`),
     and retention keeps 2 per prefix (`config/storage.yml:112`). NAS-private files (OPNsense
     `config-*.xml`, the vzdump of 101 and 102) go to `<nas_private_root>/pre-release-<release>/`,
     off the shared tree and offsite;
   - run `utils/backup/rclone-offsite.sh` again and require `.offsite-ok` newer than the copy
     (`run-all.sh` ignores an offsite failure, and the previous night's marker passes the 26 h
     check);
   - the release PR lists every artefact, each non-empty and carrying this run's stamp: one dump
     per database in `pg_database` plus `immich`, one tar per volume in `volumes.sh`, the HA tar,
     the OPNsense config, the vzdump of 101 and 102. `check-fresh.py` alone does not count;
   - an image update of an app whose state is not in `volumes.sh` goes ahead only with a tar of
     that volume made in this window (stop, tar in the `volumes.sh` format, start), unless an
     earlier R1 item added the volume to `volumes.sh`. Its rollback is a revert plus an untar of
     that tar;
   - the `pre-release-*` folders stay until the next release passes its gate; deleting them is
     asked.
4. Infra Plan Prod on the draft release PR must show no VM replace and no destroy. It plans with
   `-refresh=false` against the state (`infra-plan.yml:47-50`), so it shows what the release
   changes, not drift. When an earlier window changed a prod host, the operator can see drift
   before the merge: `gh workflow run "Infra Apply Prod" --ref main -f gate=true`, read the plan
   job and reject at `prod-gate` before merging (a waiting run holds the `infra-apply-prod`
   concurrency group, `infra-apply-prod.yml:19-21`). After the merge, Infra Apply Prod plans with
   refresh and `utils/tf-plan-risk.py` sends every VM change, delete, replace, import or unknown
   type to `prod-gate`; the operator rejects a plan that replaces or destroys a VM. After a
   rejection `main` is ahead of prod: the release merge is reverted on `main` through a PR, or
   fixed in `develop` and released again, before any other merge to `main`.
5. Rollback of an image update by revert holds only for a pinned tag whose update the store check
   cleared; a floating tag is pinned before it is updated.

Release 2, per item:

- DROP DATABASE only for a name that R1 removed from the `postgres-init` loop and only once that R1
  change runs on prod (otherwise the next deploy recreates it empty); after a dump that restores
  on DEV, kept in `pre-release-r2/`. DROP ROLE of the same name goes with it; if it fails because
  the role still owns objects, stop and report (no `DROP OWNED`). Each DROP is confirmed by the
  operator. After the next nightly backup, check that the database was not recreated and the
  pre-DROP dump is still there. Dropping `todo_grocery`, if the operator chooses it, also updates
  `knowledge/rebuild.md:121`.
- App moves to Postgres: the old file is kept next to the dump until the operator accepts the
  release.
- pve-hardening: the steps and restore commands in section 3.3 item 5.
- admin-certs, in the window: HA's current http configuration saved; certificate installed and HA
  switched; release merged (deploy-storage copies the new `ha.py` and `storage.yml` to the NAS);
  `homelab-nas-backup.service` started by hand, `journalctl -u homelab-nas-backup` shows a new
  `ha-full-*.tar` and `check-fresh.py --env prod --dry-run` reports `homeassistant` and
  `homeassistant-yaml` fresh; `HL_SKIP_WHEN_UNREACHABLE=0 utils/run-tests.sh --env prod --suite ha`
  passes with `api` PASS, not SKIP. If any check fails, HA goes back to its saved configuration
  and the PR is reverted before the window closes. After the window, the issuer and notAfter of
  both names are read and recorded.
- Immich Postgres 14: rehearse on DEV by restoring the prod window dump into the target image in
  a scratch database (no prod data into DEV's running Immich); record the restore time and the
  peak memory of immich-postgres against `mem_limit` 768m; check that the target image provides
  every extension the dump creates (`restore-pg.sh` stops at the first error). On prod, stop
  immich-server, immich-machine-learning and the album creator before the window dump and keep
  them stopped until the restored database is checked. The new major version runs on a new volume
  (for example `immich_postgres_<major>`) filled from that dump; `immich_postgres` stays untouched.
  Compare the `media/immich` file listing before and after, since the database must match the
  files. Until the operator accepts the release, rollback is a revert that points compose back at
  `immich_postgres`; writes made after the switch are lost. Deleting `immich_postgres` is a
  separate step, asked after acceptance.

After every release: the Bitwarden check of step 1 runs again (R2 creates secrets during the
window: the PVE token, the Terraform SSH key, the Cloudflare tokens). `knowledge/` records the
changes that outlive the session with the command that reverses each one (`AGENTS.md` section
11). A release is closed only when every prod check listed in its PR is done.

## 6. Reviewers and critics

Each phase has review roles run by separate agents that did not write the change:

| Role | When | Looks for |
| --- | --- | --- |
| Completeness critic | end of Phase 0, before the operator review | every backlog item and audit question answered, every claim backed by a command or file, raw data kept off the repo |
| PR reviewer (`agents/reviewer.md`) | every PR into `develop` | correctness, conventions, tests, secrets |
| Parity critic | every PR, and the release PR as a whole | anything that behaves differently on prod than on DEV (list below) |
| Release critic | before the draft release PR is marked ready (section 5 evidence, Infra Plan Prod log) | the combined diff `main..develop`, the data-safety evidence, the rollback of each item, what the DEV tests did not cover, SKIPs |

A SKIP is not a pass (`rules/verification-and-diagnosis.md`). The release critic lists the SKIP
ids of the DEV report (`tests-dev-report.json`) and, after the deploy, compares the SKIP ids of
`tests-prod-report.json` with the last prod report before the release. A new SKIP, or a SKIP on a
check that covers a changed item, goes into the release PR as a manual prod check. The release
tag is created whenever the run has no FAIL, so a tag is not proof that the release works.

The parity critic checks each change against the known differences:

- Proxmox: nested PVE in libvirt on DEV, metal on prod; Terraform as `root@pam!terraform` on DEV,
  `homelab-prod@pam` on prod (until pve-hardening gives both the same role).
- Network: DEV has libvirt NAT and no router filter. OPNsense has no DEV twin. On prod it filters
  both ways (`docs/network.md` Cross-VLAN table): APP egress is an allowlist (TCP 80, 443, 587,
  22000, 22067; UDP 123, 3478, 22000) and reaches no private network except NAS NFS, so an APP
  container cannot reach Home Assistant, Proxmox or the router; IOT reaches APP only on the listed
  rows; LAN non-Admins are blocked only on AdminPorts; DNS from APP and IOT is redirected to
  AdGuard. Found on prod: `ef2c132` (STUN egress cut by the router), `2d266f8` (Caddy DNS-01
  through the AdGuard redirect).
- NAS: on DEV the NAS role runs on the apps guest (`ansible/environments/dev/hosts.ini`), so NFS
  is loopback, a process on apps can reach the NAS-private tree, and the guest has 6 GiB. On prod
  it is a separate 2 GiB VM sharing its subnet with IOT devices. Both run the same
  `homelab-firewall` table. Found on prod: `ec33703` (nfsd block size after the NAS RAM change)
  and `c722876` (the NAS firewall blocked the PVE storage check; DEV had the same fault unnoticed
  because its vzdump job is disabled, `knowledge/lessons-learned.md:43`). A change that writes
  from apps to a NAS path, or adds a NAS service or job, names the target tree, the firewall
  source and the extra RAM on `ubuntu-nas`.
- Streams that skip on DEV: OPNsense config backup, rclone offsite, and the vzdump job
  `homelab-vms` (created disabled on DEV, `config/storage.yml:27`; its freshness check covers prod
  only, `config/monitoring.yml:48`). A change to the NAS, its exports or firewall, or the Proxmox
  host is checked by the next 04:30 dump on prod. On prod the 'Proxmox backup job' step has
  `continue-on-error` (`apps-deploy-prod.yml:75`): read the step's outcome, not the run's.
- Media: `compose/core/docker-compose.nfs.yml` is added only on prod (`deploy-core.yml:97-101`)
  and binds the libraries of immich-server, navidrome, jellyfin, syncthing, vsum-web and
  vsum-worker to `/mnt/homelab/media/*`. For any change to these six, including an image update:
  render base plus override with the prod profiles, confirm every data path the new version uses
  is a target in the override, and after the deploy `docker inspect -f '{{json .Mounts}}'` on prod
  shows the `/mnt/homelab/media/...` sources and no new named volume at a library path.
- Mail: mailpit on DEV, Proton SMTP on prod (`config/monitoring.yml:16,19`). A change that sends
  mail needs a prod delivery check.
- TLS: Caddy uses its internal CA on DEV and a Let's Encrypt wildcard by DNS-01 on prod with
  `CLOUDFLARE_API_TOKEN` from `prod` only (`utils/gen-proxy-config.py:43-50`); without the token
  prod drops `auth` and `proxy` (`deploy-core.yml:77-86`). The certificate is kept in
  `caddy_data`, so a broken DNS module or token shows only at renewal. For a change to the Caddy
  image, caddy-dns/cloudflare or the token: the built image lists the Cloudflare DNS module, prod
  smoke `proxy/*` is PASS, and the notAfter of the prod wildcard is recorded.
- Proxy: HAProxy and ACME on the router exist only on prod.
- Home Assistant: HAOS twin on DEV, T620 on prod. `utils/ha.py` installs only Terminal & SSH and
  Uptime Kuma (`utils/ha.py:627-636`); the prod Beszel add-on is installed by hand.
- Monitoring agents: Beszel agents on prod-nas, prod-pve and prod-router are native installs that
  exist only on prod; DEV has only the container agent. No workflow runs `utils/kuma-sync.py`, and
  no test compares Kuma's monitors with `config/monitoring.yml`.
- Runner and secret source: the DEV runner runs as the laptop user, whose home holds
  `~/.homelab-secrets/<env>/` and `~/.ssh/` (`knowledge/security.md:37`). `deploy-core.yml:122-129`,
  `deploy-storage.yml:688-694`, `utils/ha.py` and `utils/kuma-sync.py` fall back to that cache. The
  prod runner (CT 110) has no cache (`tests/README.md:60`), so prod gets only what
  `apps-deploy-prod.yml` passes; an empty value turns a feature off without an error unless
  `deploy-core.yml:133-159` asserts it.
- CI: Apps Deploy Dev starts by `workflow_run`, so GitHub uses the workflow file from `main`
  (`apps-deploy-dev.yml:5`): its `env:` lines, steps and deploy-paths regex are `main`'s until a
  release, and DEV stays green from the cache without a new `env:` line.
- Secrets and environment values: environments `dev`, `dev-plan`, `prod`, `prod-plan`, plus the
  approval-only `prod-approve` and `prod-gate`. DEV passes no `RCLONE_CONFIG`, `SMTP_*` or
  `CLOUDFLARE_API_TOKEN`. Every secret name a PR adds must be in the `env:` block of the
  `apps-deploy-prod.yml` step that reads it and listed by `gh secret list --env prod` before the
  release PR is opened. A secret whose absence would silently turn off an item gets an assert
  guarded by its profile (like `VSUM_GIT_TOKEN`, `deploy-core.yml:152-159`), a prod post-deploy
  test, or a release-checklist line.
- Images: after the prod deploy each updated image's digest on prod matches the one DEV tested.
- Network flows: each change names the flows it adds (source, destination, port, protocol). Each
  must match a row of the `docs/network.md` Cross-VLAN table, and a flow into the NAS guest must
  match `config/storage.yml` `firewall`. A flow without a row needs a router or NAS firewall change
  in the release window with consent. A new admin UI publishes no host port and is reached only
  through Caddy, or publishes on 127.0.0.1 only, or its port is added to AdminPorts as a router
  change.

A change that touches one of these needs either a test that runs on prod after deploy or an
explicit manual check in the release PR. A finding the critic cannot settle on DEV is listed in
the release PR as a prod check.

## 7. Delegation and models

| Work | Model tier |
| --- | --- |
| Version and release-note lookups, doc checks | small (Haiku) |
| Well-described R1 PRs (compose, timers, docs), each with a filled task card | medium (Sonnet) |
| Phase 0 analysis, all of R2, data decisions, release critic, completeness critic | large (Opus) |
| PR reviewer and parity critic | medium for R1, large for R2 |

One model per item from start to merge (`AGENTS.md` section 13). After the Phase 0 ai-cost
measurement the operator reviews these tiers and the number of review agents per PR; until then
they stand as listed.

## 8. Out of scope

Level 4 items; any change on a prod host or the router without the operator's consent to that
change; retiring `utils/bootstrap-secrets.sh` (open question in `PROJECT-CONTEXT.md` section 8).

## 9. Operator decisions

Asked once, at the Phase 0 review unless marked otherwise. The recommendation is the default the
plan is written for.

| Decision | Options | Recommended | When |
| --- | --- | --- | --- |
| Non-public place for raw audit results | a NAS folder; another place | NAS folder next to the weekly audit reports | start of Phase 0 |
| Clean machine for backup-decrypt-drill | throwaway VM; another user account | throwaway VM without `~/.homelab-secrets` | start of Phase 0 |
| Coding agent and Trilium (section 3.5) | (a) procedure rule for the agent; (b) the operator runs every Trilium check and any prod read that needs root on `ubuntu-apps` | (a), with the operator running the NAS check of the Trilium tar | spec review |
| vsum Trilium token, if tokens cannot be scoped | (a) revoke in the R1 window; (b) accept until R2 item 1 | (a) | Phase 0 review |
| Trees without backup (`share`, `media/sync`, `media/vsum`, media libraries) | one-off copy before R1; accept the risk | copy `media/sync`; decide `share` and the libraries by size | Phase 0 review |
| Stateful volumes outside `volumes.sh` | add to `volumes.sh` in R1; hand tar per update | add the ones R1 or R2 updates | Phase 0 review |
| Floating tags `postgres:16-alpine`, `valkey:8-alpine` | pin to exact tag; explicit pull in the release | pin | Phase 0 review |
| Immich Postgres 14 after 2026-11-12 | accept until R2; separate migration | accept until R2 if an upstream path exists | Phase 0 review |
| PVE firewall and Kuma `proxmox` monitor | (a) 8006 from 192.168.20.13; (b) change the monitor; (c) accept it down | (a) | before the R2 window |
| `todo_grocery` / `prod_todo_grocery` | keep; drop after dump | drop after dump | Phase 0 review |
| Lynis | R1 item; drop | operator's call | Phase 0 review |
