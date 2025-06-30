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

variable "ubuntu_password" {
  type        = string
  description = "SHA-512 hash of the ubuntu vm cuser password"
  sensitive   = true
}

variable "environment" {
  type        = string
  description = "Deployment environment"
}

variable "vm_config" {
  type = map(object({
    vm_id              = number
    vm_name            = string
    vm_description     = string
    vm_tags            = set(string)
    bios               = string
    ram                = number
    cpu_cores          = number
    net_dev_type       = string
    vlan_tag           = optional(number)
    enable_cloud_init  = optional(bool)
    cloud_init_cidr    = optional(string)
    cloud_init_gateway = optional(string)
    cloud_init_dns     = optional(string)
    efi_disk_size      = optional(string)
    storage_type       = string
    storage_interface  = string
    storage_size       = number
    ssd_enabled        = bool
    boot_order         = optional(set(string))
    image_url          = string
    img_storage_type   = string
    img_file_format    = string
  }))
  description = "Config VMs for specific environment"
}