Status: draft
Last reviewed: YYYY-MM-DD
Scope: <area or component>

# Troubleshooting: <area>

One entry per failure mode. Add an entry only after the cause was confirmed; a suspected cause is
marked `(unverified)`.

## <Short symptom, as the user or log would show it>

- **Symptom:** <exact message or observable behaviour>
- **Where it shows:** <log file, command output, UI>
- **Cause:** <confirmed cause>
- **How to tell it apart:** <the check that distinguishes it from similar symptoms>
- **Fix:** <steps or command>; confirmed by <run, date> | (unverified)
- **Prevention:** <optional>
- **Sources:** <file:line, command, date>

## Example (fictional)

- **Symptom:** `backup.sh` exits with code 3, log line `target not mounted`
- **Where it shows:** `/var/log/backup.log`
- **Cause:** the backup disk on `server.local` was not mounted after a reboot
- **How to tell it apart:** `findmnt /mnt/backup` prints nothing; a full disk would print the mount
- **Fix:** `mount /mnt/backup`, then rerun `backup.sh`; confirmed by a manual run, YYYY-MM-DD
- **Sources:** `scripts/backup.sh:27`
