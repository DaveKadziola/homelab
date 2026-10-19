Status: verified
Last reviewed: 2026-10-19
Scope: F9 repeat rebuild drill on nested DEV - wipe of ubuntu-apps-dev, rebuild from repo + vault + `rebuild.md` with no code changes

# Rebuild drill - 2026-10-19, repeat (F9, nested DEV)

Repeat of `rebuild-drill-2026-10-19.md` after #16-#23. Code at `homelab-v2` `e0bb03a`. A fresh backup
(`homelab-backup.service`, 00:43 UTC) was copied to the laptop, then the operator destroyed VMID 101
(`qm destroy 101 --purge`). Steps 3 -> 4 -> 5 -> 6 -> 7 -> 9 of `rebuild.md`, variant "Nested DEV".

**Result:** pass, with **no code change**. Two runbook gaps in step 7, both documentation, fixed in
the same change as this report. Wipe to green tests: about 30 minutes (00:45 -> 01:15 UTC).

## Timeline and evidence

| Step | What happened | Evidence |
| --- | --- | --- |
| 3 Terraform | `utils/dev-apply-local.sh`: `Plan: 1 to add, 0 to change, 0 to destroy`; 34 s | local run, 00:45 |
| 3 verify | cloud-init `done` after ~3 min; 2 vCPU / 6 GB / 26 GB; `sudo -n true` 0.012 s (#19); old host key removed with `ssh-keygen -R` (runner runs as the same user) | ssh |
| 4-6 | one `Apps Deploy Dev` dispatch: deploy-core + deploy-storage + bootstrap, no rerun; grocery image built, DB + schema created, stack created by `portainer.sh` (#21) | run 39182504361 |
| 6 | bootstrap PASS for all apps, Homarr SKIP (known); WARNs: pgAdmin HTTP login check, Beszel system registration 400 (known, agent stays off) | same run |
| 4-6 tests | post-deploy tests TOTAL 141 PASS, 0 FAIL | same run |
| 7 restore | backups put back from the laptop; `restore-pg.sh --replace` (#22) over the fresh databases: linkwarden 18 tables owner `linkwarden`; immich sessions 18 / geodata 228820 / users 1 = counts in the dump; todo_grocery 5 tables, 2 tasks; linkwarden 200, grocery 200, immich `isInitialized` true | psql counts, curl |
| 9 tests | `run-tests.sh --env dev --suite all`: 159 PASS, 0 FAIL; `--suite restore`: 10 PASS | 01:15 |

## Gaps found

| # | Gap | Fix |
| --- | --- | --- |
| 1 | Step 7 said to copy the backups off the guest, not how to put them back on the rebuilt one | `rebuild.md` step 7: tar commands both ways |
| 2 | Step 7 command failed as written (`POSTGRES_PASSWORD missing`): on the guest the secrets are in `/opt/homelab/secrets`, which step 6 passes and step 7 did not | `rebuild.md` step 7: `cd /opt/homelab` + `sudo env HOMELAB_SECRETS_DIR=...` |

Operator note, not a repo gap: a restore script piped to `ssh ... bash -s` stops after the first
`restore-pg.sh`, because its `docker exec -i` reads the rest of the script from stdin. Noted in step 7.

Not exercised (same as before): volume-tar restore, Homarr password, Zotify OAuth, Syncthing peers.

## Gate (merge `homelab-v2` -> `main`)

- [x] Nested rebuild using only repo + vault + `rebuild.md` - this drill; the two gaps above were
      runbook wording, resolved from the runbook itself (step 6 prefix) and the operator's own copy
- [ ] nmap from WG/IOT/APP (S7) - needs prod
