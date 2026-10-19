# Portainer

| | |
|--|--|
| URL (dev) | http://192.168.122.50:9000 (also `:9443`) |
| Login | username `admin` |
| Secret | `~/.homelab-secrets/<env>/PORTAINER_ADMIN_PASSWORD` |
| Volume | `homelab-core_portainer_data` |
| Bootstrap | `utils/bootstrap/portainer.sh` |
| Config-as-code | partial (admin only; stacks stay in Portainer) |

First start locks itself if no admin is created quickly. Bootstrap uses `portainer/helper-reset-password` (parse `login: \`…\``) then the API to set the declared secret.

Legacy file `~/.homelab-portainer-dev-pass` is **stale** after a helper reset.

Grocery is deployed here as stack `easytodo-grocery` — see [`grocery.md`](grocery.md).
