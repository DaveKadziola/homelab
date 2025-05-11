locals {
  vm_config_homeassistant = {
    for k, v in var.vm_config : k => v if contains(["homeassistant"], k)
  }

  vm_config_docker = {
    for k, v in var.vm_config : k => v if contains(["docker"], k)
  }
}