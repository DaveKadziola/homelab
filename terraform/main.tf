resource "null_resource" "download_and_extract" {
  provisioner "local-exec" {
    command = <<-EOT
      if [ ! -f "${var.haos_base_filename}.qcow2.img" ]; then
        wget ${var.haos_download_url} -O ${var.haos_base_filename}.qcow2.xz
        xz -d ${var.haos_base_filename}.qcow2.xz
        mv ${var.haos_base_filename}.qcow2 ${var.haos_base_filename}.qcow2.img
      else
        echo "File ${var.haos_base_filename}.qcow2.img exists, skipping download."
      fi
    EOT
  }
}
resource "proxmox_virtual_environment_file" "vm_image" {
  for_each     = { for k, v in var.vm_config : k => v if contains(["homeassistant"], k) }
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.environment

  source_file {
    path         = "${var.haos_base_filename}.qcow2.img"
  }
  overwrite    = true
}

resource "proxmox_virtual_environment_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.environment
  source_file {
    path = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  }
  overwrite    = true
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each    = var.vm_config
  name        = "${each.key}-${var.environment}"
  description = "Managed by Terraform"
  node_name   = var.environment
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
      file_id      = proxmox_virtual_environment_file.vm_image[each.key].id
      interface    = "virtio0"
      size         = 32
      file_format  = "qcow2"
    }
  }

  dynamic "disk" {
    for_each = contains(["docker"], each.key) ? [1] : []
    content {
      datastore_id = each.value.storage
      file_id      = proxmox_virtual_environment_file.ubuntu_cloud_image.id
      interface    = "virtio0"
      size         = 10
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
