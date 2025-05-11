provider "proxmox" {
  endpoint = var.proxmox_api_url
  insecure = true
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
}
