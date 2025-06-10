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

variable "proxmox_ssh_username" {
  type        = string
  description = "Proxmox SSH username"
}

variable "proxmox_ssh_password" {
  type        = string
  description = "Proxmox SSH password"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
}

variable "vm_config" {
  type = map(object({
    vm_id             = number
    vm_name           = string
    vm_description    = string
    vm_tags           = set(string)
    ram               = number
    cpu_cores         = number
    net_dev_type      = string
    cidr              = string
    gateway           = string
    dns               = string
    storage_type      = string
    storage_interface = string
    storage_size      = number
    file_format       = string
    img_storage_type  = string
    image_url         = string
  }))
  description = "Config VMs for specific environment"
}