environment = "dev"

proxmox_api_token_id = "terraform-prov@pve!terraform-token-dev"
proxmox_api_url = "https://192.168.122.219:8006"
proxmox_api_token_secret = "0c007f2f-8189-490d-ae0d-0fd898b45e2e"

proxmox_ssh_username = "root"
proxmox_ssh_password = "guziec123"

vm_config = {
  homeassistant = {
    cores     = 2
    memory    = 4096
    ip        = "192.168.122.220/24"
    storage   = "local-lvm"
    vm_id     = 100
  }
  docker = {
    cores   = 1
    memory  = 1024
    ip      = "192.168.122.221/24"
    storage = "local-lvm"
    vm_id   = 101
  }
}
