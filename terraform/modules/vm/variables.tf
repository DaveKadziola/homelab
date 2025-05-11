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