# Rebuild drill — 2026-09-10 (F9-F3)

**This was a tabletop + script-existence walk, not a wipe.**

`docs/kb/rebuild.md` says to rebuild nested PVE from repo + backups only. Doing that for real would **destroy** `ubuntu-apps-dev` (Immich volumes, grocery DB, Portainer). There are **no F5 backups** to restore afterwards. The live DEV stack stays up.

**Merge `homelab-v2` → `main`:** **FAIL** this gate until (1) F5 backup jobs exist and a restore was proven, (2) a second nested guest (or a planned wipe) completes `rebuild.md` without chat memory, (3) Bitwarden holds the current cache.

Clock below is “stranger with this repo + Bitwarden + this laptop”, not wall time of a real apply.

---

## Walk of `rebuild.md`

| Step | Auto? | Script / doc exists? | Would a stranger improvise? | Est. |
|------|-------|----------------------|-----------------------------|------|
| 0. Secrets | manual | `gen-app-credentials.sh` creates **new** values; does not export the existing cache | **Yes** — must already have Bitwarden. No `bw` helper. | 20–40 min |
| 1. OPNsense | manual | `docs/opnsense-baseline.md`, gitignored XML on this laptop | DEV: skip. Prod: need the XML in Bitwarden (S9). | 30–90 min |
| 2-DEV. Nested PVE | semi | `ensure-dev-proxmox.sh`, `bootstrap-dev-proxmox.sh` | Node name `dev` is documented. Token paste is interactive. | 30–60 min |
| 3-DEV. Terraform | auto | `dev-apply-local.sh` | **Yes** — must not apply a VM replace; local state is gitignored (only on this laptop). New laptop = new state, maybe a **second** VM. | 15–30 min |
| 4. Ansible | auto | `deploy-core.yml` | **Yes** if GHA: workflows were missing F7 secrets (S14). Laptop ansible with cache works. | 10–20 min |
| 5. Grocery | Portainer | `compose/grocery/` + `docs/kb/apps/grocery.md` | **Yes** — stack is not in `bootstrap-apps.sh`. Image `easy-todo-grocery-nodb:latest` is local, not pulled from GHCR. | 15 min |
| 6. F7 bootstrap | auto | `bootstrap-apps.sh` | Homarr CLI skip, Zotify OAuth, Syncthing peers, Beszel agent key. Immich/Navidrome need `python3-pexpect`. | 5–15 min |
| 7. Restore | missing | F5 not implemented | **Cannot.** Empty libraries only. | — |
| 8. HAProxy | prod | docs only | Skip on DEV. | — |
| 9. Tests | auto | `utils/run-tests.sh` | DEV config suite green today. Infra needs TF creds + local state. | 5–20 min |

**Improvisation log (gaps → backlog)**

1. **No export-from-cache** — `gen-app-credentials.sh --all` skips names already in GH, so it will not produce a Bitwarden file for the *current* passwords.
2. **TF state is not in the repo** — a new laptop cannot `plan` against the live guest without pulling state from somewhere undocumented.
3. **Grocery image is local** — rebuild needs a build recipe or a registry.
4. **GHA deploy ≠ playbook** — until S14 is confirmed green on the runner.
5. **`create-dev-vm.sh`** still looks like the DEV path if you sort `utils/` by name.
6. **Restore is a hole** — the runbook is honest; the drill therefore cannot pass.

---

## What we did verify (non-destructive)

- `rebuild.md` steps 2–6 map to real files.
- `config` tests PASS=64.
- Live DEV logins match `~/.homelab-secrets/dev` (2026-09-10 evening).
- Prod IPs do not answer from this laptop — no prod rebuild attempt.

---

## Gate checklist (merge to `main`)

- [ ] Bitwarden contains every name in `config/identities.yml` for **prod** (and remaining **dev**)
- [ ] F5: `pg_dump` + volume/NFS + rclone job has run once
- [ ] `tests/restore/` (C4) exists and PASSes on a copy
- [ ] Nested rebuild (new VMID or planned wipe) completed using only repo + vault + `rebuild.md`
- [ ] nmap from WG/IOT/APP (S7)
- [ ] GHA `apps-deploy-*` injects the full secret set (this change) and a DEV test workflow runs
