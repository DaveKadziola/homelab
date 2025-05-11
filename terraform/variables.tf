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