provider "proxmox" {
  endpoint = var.proxmox_api_url
  insecure = true
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  ssh {
    agent = true
    username = var.proxmox_ssh_username
    password = var.proxmox_ssh_password
  }
}
