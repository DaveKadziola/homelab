# Homelab
## Description
### Deployed software
## Setup
1. Install Proxmox using [Proxmox VE x.x ISO Installer](https://www.proxmox.com/en/downloads).
2. Logon to Proxmox and run the [Proxmox VE Post Install](https://community-scripts.github.io/ProxmoxVE/scripts?id=post-pve-install) script using shell or ssh connection:
   ```bash
   bash -c "$(wget -qLO - https://github.com/community-scripts/ProxmoxVE/raw/main/misc/post-pve-install.sh)"
   ```
   By default you can answer `yes` for every question.
