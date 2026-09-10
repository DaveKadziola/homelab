# Deployment

## Path of a change

1. Commit on `homelab-v2` (dev) or `main` (prod, approval).
2. GHA on the matching self-hosted runner.
3. Terraform (infra workflows) and/or Ansible `deploy-core.yml` then `deploy-storage.yml` (apps workflows).
4. Ansible syncs `compose/`, `config/`, `utils/bootstrap*` to `/opt/homelab/`, writes `.env` **without literal secret fallbacks**, copies secrets to `/opt/homelab/secrets/<env>/`, runs `utils/bootstrap-apps.sh` unless `HOMELAB_SKIP_BOOTSTRAP` is set.

Manual DEV deploy from the laptop:

```bash
export HOMELAB_ENV=dev
export COMPOSE_PROFILES=auth,media
export LINKWARDEN_URL=http://192.168.122.50:3001
while IFS= read -r f; do
  export "$(basename "$f")=$(tr -d '\r\n' < "$f")"
done < <(find ~/.homelab-secrets/dev -type f)

ansible-playbook -i ansible/environments/dev/hosts.ini ansible/playbooks/deploy-core.yml
ansible-playbook -i ansible/environments/dev/hosts.ini ansible/playbooks/deploy-storage.yml
```

Skip bootstrap (compose only): `HOMELAB_SKIP_BOOTSTRAP=1`.

## Bootstrap

`utils/bootstrap-apps.sh --env dev --host 127.0.0.1` (on the apps VM) runs, in order:

`portainer` → `pgadmin` → `authelia` → `linkwarden` → `immich` → `jellyfin` → `navidrome` → `syncthing` → `beszel` → `homarr`

Exit: `0` OK, `2` SKIP (container missing or documented limit), `1` FAIL.

On the VM:

```bash
sudo env HOMELAB_SECRETS_DIR=/opt/homelab/secrets \
  HOMELAB_CONFIG_DIR=/opt/homelab/config \
  HOMELAB_COMPOSE_DIR=/opt/homelab/compose \
  /opt/homelab/utils/bootstrap-apps.sh --env dev --host 127.0.0.1
```

## Grocery

Not in `compose/core`. Portainer stack `easytodo-grocery` from `compose/grocery/` (bridge `8101:8101`, `DB_HOST=host.docker.internal`). Repo: `DaveKadziola/easytodo-grocery-list`.

## Local Terraform (dev)

```bash
./utils/dev-apply-local.sh
```

Do **not** `terraform apply` if the plan wants to **replace** `ubuntu-apps`. That wipes Docker volumes.

## Related

- [`docs/f4-apps-dev.md`](../f4-apps-dev.md)
- [`operations.md`](operations.md)
