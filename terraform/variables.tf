variable "proxmox_api_url" {
  type        = string
  description = "Proxmox API endpoint URL"
}

variable "proxmox_api_user" {
  type        = string
  default     = "terraform-prov"
  description = "Proxmox API user"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "Proxmox API token ID"
}

variable "proxmox_api_token_secret" {
  type        = string
  sensitive   = true
  description = "Proxmox API token secret"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev/prod)"
}

variable "proxmox_ssh_username" {
  type        = string
  description = "Proxmox SSH username"
}

variable "proxmox_ssh_password" {
  type        = string
  description = "Proxmox SSH password"
}

variable "vm_config" {
  type = map(object({
    cores     = number
    memory    = number
    ip        = string
    storage   = string
    vm_id     = number
    image_url = optional(string)
  }))
  description = "Config VMs for specific environment"
}

variable "haos_download_url" {
  description = "Home Assistant source URL"
  default     = "https://github.com/home-assistant/operating-system/releases/download/15.2/haos_ova-15.2.qcow2.xz"
}

variable "haos_base_filename" {
  description = "Home Assistant base file name"
  default     = "homeassistant"
}

variable "haos_download_directory" {
  description = "Target directory for Home Assistant download"
  default     = "/var/local"
}