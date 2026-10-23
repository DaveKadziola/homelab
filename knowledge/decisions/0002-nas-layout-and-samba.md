Status: verified
Last reviewed: 2026-10-19
Scope: NAS disk layout and file access for people (Samba) on `ubuntu-nas`

# 0002 - Split the NAS disks by data type and serve files with Samba on the Ubuntu NAS

## Context

- Two whole disks go to `ubuntu-nas`: WD Red SA500 2 TB SSD and WD Purple 4 TB HDD. SMART
  2026-10-19: SA500 PASSED, 37 h; Purple PASSED, 50733 h (~5.8 years), no reallocated or pending
  sectors. Both hold NTFS today.
- The earlier plan (A15, 2026-06-11) set a size cap per library (`cap_gb` in
  `config/storage.yml`); no code read it. Media totals ~300-400 GB.
- Besides NFS for the apps VM, people need file access: one admin and a few users, for installers
  and the music and video libraries. Windows network discovery does not cross VLANs.
- The NAS sits in IOT VLAN 20 next to IOT devices, which the router cannot filter.
- Both disks carry NTFS, so the first format erases it; a format must not happen by accident, in
  CI or in a DR rebuild.

## Options considered

| Option | For | Against |
| --- | --- | --- |
| Layout by data type: SSD = all media, Purple = backups + share | one filesystem per kind of data; media fits the SSD with room to spare | backups and the share sit on one disk |
| Split video onto the HDD | frees SSD space | not needed: ~300-400 GB of media fits the 2 TB SSD |
| Size caps per library (`cap_gb`) | limits growth | never enforced by code |
| Samba on the Ubuntu NAS | same Ansible and `config/storage.yml` as NFS; one generated `smb.conf` | Samba config is maintained here |
| NAS distro (OpenMediaVault / TrueNAS) | UI, more sharing features | one admin and a few users do not justify it; see `knowledge/storage.md` "Why Ubuntu, not a NAS distro" |
| FTP | simple clients | rejected: plain-text passwords |
| NFS for the clients | already running | awkward on Windows |

## Decision

- SA500 = all media (Immich, music, video, Syncthing sync) at `/export/media`. Purple = backups
  (`/srv/purple/backups`, bind-mounted to `/export/backups`) + Samba share `share` (installers,
  `/srv/purple/share`), mounted at `/srv/purple` outside the NFS tree. No size caps; `cap_gb` is
  removed.
- Samba on `ubuntu-nas` from `deploy-storage.yml`: shares `share` and `media`, plus `photos` (the Immich library, 2026-10-23) and `backups` read-only (added 2026-10-20 at the owner's request; a writable backups share is what ransomware on a client would use), one login
  (`homelab-admin`, username `admin`), SMB3 only, `hosts allow` = LAN + WireGuard.
- The share is not backed up and not in offsite. A homelab backup of the media to pCloud is
  deferred until prod runs; the owner will adjust the pCloud targets.
- A disk is formatted only when blank, or once with the opt-in `nas_wipe` naming its serial and a
  detected type. Never in CI or a DR rebuild.

## Consequences

- A lost Purple loses the share; the media has no homelab copy until the pCloud backup is set up.
- Samba access is controlled on the NAS by `hosts allow`, not by the router.
- New secret `SAMBA_ADMIN_PASSWORD` (inject mode `ansible`, envs dev and prod).
- Clients use `\\nas.dkhomelabserver.xyz\share` (AdGuard rewrite added 2026-10-19) or the IP.
- `knowledge/storage.md` holds the layout, the attach order and the wipe opt-in.

## Sources

- decided by the operator, 2026-10-19
- `config/storage.yml` (`passthrough`, `binds`, `samba`); `ansible/playbooks/deploy-storage.yml`
  (format opt-in, mounts, Samba)
- SMART check of both disks, 2026-10-19
- DEV tests 2026-10-19: Samba from the laptop (list, put, get, delete on `share`; wrong password
  -> `NT_STATUS_LOGON_FAILURE`; anonymous -> `NT_STATUS_ACCESS_DENIED`); `tests/storage/run.sh`
