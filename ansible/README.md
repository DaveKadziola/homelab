# ansible

Configures a guest that Terraform has already created. Inventories are `environments/dev/hosts.ini` and `environments/prod/hosts.ini`. `ansible.cfg` is the project defaults.

| Playbook | Does |
| --- | --- |
| `playbooks/ping.yml` | SSH to the inventory. Deploy runs this first |
| `playbooks/deploy-storage.yml` | Disks, NFS, Samba, and the NAS backup timer. Runs before the apps, because the apps mount NFS |
| `playbooks/deploy-core.yml` | Docker, Compose, `.env`, the secret files, and `utils/bootstrap-apps.sh` |

The GitHub deploy workflows run storage, then core. A check that the host already matches the repo is `ansible-playbook --check` of `deploy-core.yml`, which `tests/infra` does.
