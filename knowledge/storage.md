Status: draft
Last reviewed: 2026-10-21
Scope: NAS storage layout, passthrough attach and format order, Samba (dev and prod)

# Storage

Layout and env modes live in [`config/storage.yml`](../config/storage.yml). Ansible: `ansible/playbooks/deploy-storage.yml`.

## Dev (`ubuntu-apps-dev`)

Nested PVE has ~8 GiB RAM and the apps guest is already 6 GiB — there is **no second NAS VM**.

- Export tree: `/srv/homelab-export/{media/{immich,music,video,sync},backups}` (sync moved under `media/` on 2026-10-19)
- NFS loopback: `192.168.122.50:/srv/homelab-export` → `/mnt/homelab`
- No passthrough disks: the exports live on the root fs. Samba runs on the same guest (share `/srv/homelab-share`, see [Samba](#samba)).
- App **libraries stay on Docker named volumes**. The NFS compose override is **not** applied on DEV (that would hide Immich photos).

Notable volumes (compose project `homelab-core`):

| Volume | App |
|--------|-----|
| `*_postgres_data` | shared Postgres |
| `*_immich_postgres` / `*_immich_upload` / `*_immich_model_cache` | Immich |
| `*_jellyfin_config` / `*_jellyfin_media` | Jellyfin |
| `*_navidrome_data` / `*_navidrome_music` | Navidrome |
| `*_portainer_data` | Portainer |
| `*_homarr_data` | Homarr |
| `*_syncthing_data` | Syncthing |

Wiping a volume is a DEV-only recovery tool (see [`apps/jellyfin.md`](apps/jellyfin.md)). Never do this on prod.

## Prod

Layout by data type, not quotas (decision [0002](decisions/0002-nas-layout-and-samba.md), owner 2026-10-19): media totals ~300-400 GB. There are no size caps; `cap_gb` was removed from `config/storage.yml` (no code read it).

| Disk | Role | How |
|------|------|-----|
| SA500 2 TB SSD | all media: Immich, music, video, Syncthing sync (`/export/media`) | slot `scsi1` with `ssd=1,discard=on`, serial `2525GTD00073`, ext4 `LABEL=hl-media` |
| Purple 4 TB HDD | backups + Samba share `share` (installers); mounted at `/srv/purple`, outside the NFS tree | slot `scsi2`, serial `WD-WCC7K3KZKJKX`, ext4 `LABEL=hl-purple`; `/srv/purple/backups` is bind-mounted to `/export/backups` |
| apps 48G | images + small state | TF sized; VM 101 runs since 2026-10-20 |

By-id paths are in `config/storage.yml` `passthrough[]`. The share (`/srv/purple/share`) is neither NFS-visible nor in backups/offsite. SMART 2026-10-19: SA500 PASSED (37 h); Purple PASSED (50733 h, ~5.8 years, no reallocated or pending sectors). Both held NTFS until the one-time wipe (below); on prod both are attached and mounted by LABEL since 2026-10-20 (check: `utils/run-tests.sh --env prod --suite storage`, `disk/<label>@<path>`).

`ubuntu-nas` `.20.12` exports `/export`. `ubuntu-apps` `.50.30` mounts it at `/mnt/homelab`. Compose then uses [`compose/core/docker-compose.nfs.yml`](../compose/core/docker-compose.nfs.yml).

Firewall APP → NAS `:2049` / `:111` is an F2 rule — see [`docs/network.md`](../docs/network.md). Until 2026-10-19 the rules carried the port where pf ignores it and passed every TCP port; `utils/f2-opnsense-nas-ports.sh` fixed them on the router and added SSH `:22` from `192.168.50.30` only. SMB `:445` is limited by Samba `hosts allow`, not by the router.

### Attach and format (run order)

1. `terraform apply`, then `terraform plan` - no drift.
2. `./utils/pve-attach-nas-disks.sh --env prod --dry-run`, then without `--dry-run` (optional `PVE_KEY`). Fixed slots, `serial=` and, for the SSD, `ssd=1,discard=on` come from the config; a bad by-id, slot or serial fails the run. On the host it checks first: VM exists, by-id exists, disk not mounted and not an LVM PV, slot free (the same disk with the same options already there -> skip; PVE stores the options sorted and adds `size=`, so the check ignores both, see `--self-test`; `qm config 102`, 2026-10-20: `scsi1: ...,serial=2525GTD00073,size=1953514584K,ssd=1`).
3. `terraform plan` again - still no changes. On DEV (bpg 0.77.1) a disk attached with `qm set` outside Terraform gave "No changes"; that test used a pool volume, not a raw device.
4. `deploy-storage.yml` once with the wipe opt-in below.
5. Normal deploys, without `nas_wipe`.

**One-time wipe opt-in.** The NAS play finds each passthrough disk by serial (`lsblk`). A disk that already carries its LABEL is never touched; a blank disk is formatted. A disk with any signature (`wipefs`/`lsblk` types, e.g. `gpt ntfs`) is refused unless the run passes `-e '{"nas_wipe": ["<serial>:<type>"]}'` naming one detected type; then `wipefs` + `mkfs.ext4 -L <label>`. **Never pass `nas_wipe` in CI or a DR rebuild.**

**Mounts.** fstab mounts by LABEL with `nofail,x-systemd.device-timeout=30s`; the bind has `x-systemd.requires-mounts-for`; mounting is idempotent (`mountpoint` check). A systemd drop-in makes `nfs-server` `RequiresMountsFor` every NAS mount: tested on DEV, with a disk missing nfs-server refuses to start and exports nothing, instead of exporting the empty root-disk directories. Each NFS-visible filesystem carries a marker `.homelab-fs-<label>`; the client play checks them through NFS and drops the dentry cache once when a marker is not visible yet (DEV showed a stale client view of a directory the NAS had mounted over). `/etc/exports` has `crossmnt`: the client sees `/mnt/homelab/media` and `/mnt/homelab/backups` as submounts (verified). On prod `docker.service` gets a drop-in `RequiresMountsFor=/mnt/homelab`, and the deploy workflows run `deploy-storage` before `deploy-core`, so NFS is up before compose binds the libraries.

## Samba

Set up by `deploy-storage.yml` on `ubuntu-nas` (on DEV on the apps guest):

- Shares `share` (`samba.share_path`: prod `/srv/purple/share`, DEV `/srv/homelab-share`) and `media` (`export_root/media`; the Immich directory and the marker files are vetoed), plus `backups` (`export_root/backups`) **read-only** since 2026-10-20: a client with ransomware must not reach the only local backups; the session runs as `homelab-smb`, which owns nothing there, and a write is refused (`samba/backups-ro`).
- Login: identity `homelab-admin`, username `admin`, mapped (`username map`) to the Unix account `homelab-smb` (system, nologin). Not a Unix user `admin`: Ubuntu's `%admin` sudoers group would grant it sudo; `homelab-smb` has no sudo (verified). `force user` = the ansible user, the owner of the export tree.
- SMB3 only, NetBIOS / `nmbd` off, no guest. `hosts allow` = prod LAN `192.168.1.0/24` + WireGuard `10.10.10.0/24` + `127.0.0.1` (DEV `192.168.122.0/24` + `127.0.0.1`), `hosts deny = ALL`. IOT devices share the NAS subnet and the router cannot filter them, so `hosts allow` is the control.
- Password: `SAMBA_ADMIN_PASSWORD` (`inject: ansible` in `config/identities.yml`), from the environment (GH envs dev and prod) or `~/.homelab-secrets/<env>/`.
- Clients: `\\nas.dkhomelabserver.xyz\share` (AdGuard rewrite `nas` -> `192.168.20.12`, added 2026-10-19) or the IP. Windows network discovery does not cross VLANs.
- Verified on DEV from the laptop (2026-10-19): list, put, get, delete on `share`; `media` lists `music`, `video`, `sync` without `immich`; wrong password -> `NT_STATUS_LOGON_FAILURE`; anonymous -> `NT_STATUS_ACCESS_DENIED`.

Checks: `utils/run-tests.sh --env <env> --suite storage` (part of `--suite all`, see [`tests/README.md`](../tests/README.md)).

## Why Ubuntu, not a NAS distro

`ubuntu-nas` is a **thin NFS + Samba server**, not a home NAS appliance. The guest passes through SA500 + Purple, exports `/export` to `ubuntu-apps` and serves three Samba shares (one of them read-only) to one login (one admin + a few users, decision [0002](decisions/0002-nas-layout-and-samba.md)). Docker, Postgres, Immich, and the backup timer already live on the apps VM. Decision **B6/B7**: 4 GiB RAM for NAS next to 8 GiB apps on a Celeron J4205.

A dedicated distro would solve a different problem (SMB for many clients, a web UI, ZFS pools, plugins). It would not make F5 smaller.

| Option | Fit here | Why not (today) |
|--------|----------|-----------------|
| **Ubuntu cloud image** (current) | Same Terraform, cloud-init, SSH, and Ansible as `ubuntu-apps`. `nfs-kernel-server` + `/etc/exports` and `smbd` with a generated `smb.conf` are the whole NAS role. | — |
| **OpenMediaVault** | Debian, lighter than TrueNAS, decent UI. | Config lives in the OMV UI / salt, not `config/storage.yml`. Second image, second admin account, same NFS at the end. DEV still cannot run a second VM. |
| **TrueNAS** (CORE / SCALE; formerly FreeNAS) | Real ZFS (scrub, snapshots) if you have the RAM. | ZFS ARC wants far more than **4 GiB**. Second OS family, different updates and DR than the rest of the IaC. Two pass-through disks and ~300-400 GB of media do not pay for that. |

Keep Ubuntu until one of the triggers below is true. Do not swap distros “because NAS products exist”.

### When to move to a NAS distro

Revisit only if several of these land:

1. A third / fourth disk and you actually want **ZFS** (mirrors, scrub, snapshots) rather than two independent volumes.
2. Many **SMB/AFP clients** (TVs, Windows laptops) — not one Samba login and one apps VM on NFS.
3. You would rather operate storage from a **UI** than from git + Ansible.
4. The NAS RAM budget grows well above 4 GiB (TrueNAS), or you accept OMV’s UI as the source of truth.

If you switch: replace the **guest OS** only. Keep IP **`192.168.20.12`**, VLAN 20, the `/export` layout, and APP→NAS `:2049`. Then OMV, not TrueNAS, unless the host has been upsized. Nested DEV stays loopback NFS on `ubuntu-apps-dev`.

## Related

- [`backup.md`](backup.md) · [`dr.md`](dr.md) · [`docs/f5-storage.md`](../docs/f5-storage.md)
