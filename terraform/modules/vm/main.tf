resource "proxmox_virtual_environment_download_file" "vm_image" {
  for_each     = { for k, v in var.vm_config : k => v if contains(["homeassistant"], k) }
  content_type = "iso"
  datastore_id = "local"
  node_name    = "pve"
  url          = each.value.image_url
  overwrite    = true
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each    = var.vm_config
  name        = "${each.key}-${var.environment}"
  description = "Managed by Terraform"
  node_name   = "pve"
  vm_id       = each.value.vm_id

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
  }

  network_device {
    bridge = "vmbr0"
  }

  dynamic "disk" {
    for_each = contains(["homeassistant"], each.key) ? [1] : []
    content {
      datastore_id = each.value.storage
      file_id      = proxmox_virtual_environment_download_file.vm_image[each.key].id
      interface    = "virtio0"
      size         = 32
      file_format  = "qcow2"
    }
  }

  dynamic "disk" {
    for_each = contains(["docker"], each.key) ? [1] : []
    content {
      datastore_id = each.value.storage
      interface    = "virtio0"
      size         = 32
      file_format  = "qcow2"
    }
  }

  initialization {
    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = var.environment == "dev" ? "192.168.1.1" : "192.168.2.1"
      }
    }
    dns {
      servers = ["192.168.1.100"]
    }
  }
}
