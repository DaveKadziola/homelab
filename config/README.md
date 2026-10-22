# config

Declared once. Compose, Ansible, tests, and the proxy read these files. They do not contain secret values.

| File | Does |
| --- | --- |
| `services.yml` | Every app: port, profile, health check, public name, Authelia exceptions |
| `identities.yml` | Account names and which secret name holds the password |
| `storage.yml` | Disks, NFS exports, Samba, and the Home Assistant URL per environment |
| `monitoring.yml` | Uptime Kuma monitors, Beszel thresholds, backup ages, SMTP |
| `pve/interfaces.dev` | Network file for the nested Proxmox. `utils/pve-network.py --env dev` writes it to the host |
| `pve/interfaces.prod` | The same for the physical host |
