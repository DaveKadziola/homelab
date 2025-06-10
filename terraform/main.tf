resource "proxmox_virtual_environment_file" "vm_image" {
  for_each     = var.vm_config
  content_type = "iso"
  datastore_id = each.value.storage_type
  node_name    = var.environment

  source_file {
    path = each.value.image_url
  }

  overwrite = true
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each    = var.vm_config

  name        = "${each.value.vm_name}-${var.environment}"
  description = each.value.vm_description
  node_name   = var.environment
  vm_id       = each.value.vm_id
  tags        = each.value.vm_tags

  cpu {
    cores = each.value.cpu_cores
  }

  memory {
    dedicated = each.value.ram
  }

  network_device {
    bridge = each.value.net_dev_type
  }

  disk {
    datastore_id = each.value.storage_type
    file_id      = proxmox_virtual_environment_file.vm_image[each.key].id
    interface    = each.value.storage_interface
    size         = each.value.storage_size
    file_format  = each.value.file_format
  }

  initialization {
    ip_config {
      ipv4 {
        address = split("/", each.value.cidr)[0]
        gateway = each.value.gateway
      }
    }

    dns {
      servers = [each.value.dns]
    }
  }
}
