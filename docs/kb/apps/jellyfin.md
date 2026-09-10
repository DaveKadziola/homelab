# Jellyfin — headless limits

The `/Startup/*` wizard only runs once. After `StartupWizardCompleted=true`,
Jellyfin has no supported CLI to reset the admin password.

If bootstrap reports that `admin` cannot log in, the account was created by
the first-run UI (or an earlier wizard) with a password that is not in the
secret cache.

Recover:

```bash
# Destructive — wipes Jellyfin config and re-runs the wizard on next bootstrap.
ssh -i ~/.ssh/homelab_dev_ed25519 ubuntu-dev@192.168.122.50 \
  'docker compose -f /opt/homelab/compose/core/docker-compose.yml stop jellyfin
   docker volume rm homelab-core_jellyfin_config
   docker compose -f /opt/homelab/compose/core/docker-compose.yml up -d jellyfin'
./utils/bootstrap/jellyfin.sh --env dev --host 192.168.122.50
```

Do this only on DEV. On prod, reset the password from the UI and then store
it with `utils/gen-app-credentials.sh --env prod --secret JELLYFIN_ADMIN_PASSWORD --rotate`.
