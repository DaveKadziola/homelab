#Config node
resource "proxmox_virtual_environment_certificate" "node_ssl_setup" {
  for_each          = var.node_config.cert_setup_enabled ? { "ssl_setup" = true } : {}
  node_name         = var.environment
  certificate       = var.ssl_cert
  certificate_chain = var.ssl_cert_chain
  private_key       = var.ssl_cert_pkey
}

resource "proxmox_virtual_environment_dns" "node_dns_setup" {
  for_each  = var.node_config
  node_name = var.environment
  domain    = each.value.dns_domain
  servers   = each.value.dns_servers
}

resource "proxmox_virtual_environment_network_linux_bridge" "vmbr0" {
  for_each  = var.node_config
  node_name = var.environment

  depends_on = [
    proxmox_virtual_environment_network_linux_vlan.vlan20
  ]

  name       = each.value.bridge_name
  address    = each.value.bridge_address
  gateway    = each.value.bridge_gateway
  vlan_aware = each.value.vlan_aware
}

resource "proxmox_virtual_environment_network_linux_vlan" "vlan20" {
  for_each  = var.node_config
  node_name = var.environment
  name      = each.value.vlan_name
  address   = each.value.vlan_address
  gateway   = each.value.vlan_gateway
  comment   = "VLAN 20 for IOT"
}

#Config VMs
resource "proxmox_virtual_environment_file" "cloud_config" {
  for_each = { for k, v in var.vm_config : k => v if try(v.enable_cloud_init, false) }

  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.environment
  source_raw {
    data = templatefile("${path.module}/cloud-init-user-data.yaml.tpl", {
      ubuntu_password = var.ubuntu_password
    })
    file_name = "ubuntu-cloud-init-user-data.yaml"
  }
}

resource "proxmox_virtual_environment_file" "vm_image" {
  for_each     = var.vm_config
  content_type = "iso"
  datastore_id = each.value.img_storage_type
  node_name    = var.environment

  source_file {
    path = each.value.image_url
  }

  overwrite = true
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vm_config

  name        = "${each.value.vm_name}-${var.environment}"
  description = each.value.vm_description
  node_name   = var.environment
  vm_id       = each.value.vm_id
  tags        = each.value.vm_tags

  bios = each.value.bios

  boot_order = each.value.boot_order
  cpu {
    cores = each.value.cpu_cores
  }

  memory {
    dedicated = each.value.ram
  }

  network_device {
    bridge  = each.value.net_dev_type
    vlan_id = each.value.vlan_tag
  }

  efi_disk {
    type = each.value.efi_disk_size
  }
  disk {
    datastore_id = each.value.storage_type
    file_id      = proxmox_virtual_environment_file.vm_image[each.key].id
    interface    = each.value.storage_interface
    size         = each.value.storage_size
    file_format  = each.value.img_file_format
    ssd          = each.value.ssd_enabled
  }

  # cloud-init
  dynamic "initialization" {
    for_each = each.value.enable_cloud_init == true ? [1] : []
    content {
      ip_config {
        ipv4 {
          address = each.value.cloud_init_cidr
          gateway = each.value.cloud_init_gateway
        }
      }
      dns {
        servers = [each.value.cloud_init_dns]
      }
      user_data_file_id = proxmox_virtual_environment_file.cloud_config[each.key].id
    }
  }
}
