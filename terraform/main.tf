#Config node
resource "proxmox_virtual_environment_certificate" "node_ssl_setup" {
  count             = var.node_config.cert_setup_enabled ? 1 : 0
  node_name         = var.environment
  certificate       = var.ssl_cert
  certificate_chain = var.ssl_cert_chain
  private_key       = var.ssl_cert_pkey
}

resource "proxmox_virtual_environment_dns" "node_dns_setup" {
  node_name = var.environment
  domain    = var.node_config.dns_domain
  servers   = var.node_config.dns_servers
}

resource "proxmox_virtual_environment_network_linux_bridge" "vmbr0" {
  node_name = var.environment

  depends_on = [
    proxmox_virtual_environment_network_linux_vlan.vlan20
  ]

  name       = var.node_config.bridge_name
  address    = var.node_config.bridge_address
  gateway    = var.node_config.bridge_gateway
  ports      = var.node_config.bridge_ports
  vlan_aware = var.node_config.bridge_vlan_aware
}

resource "proxmox_virtual_environment_network_linux_vlan" "vlan20" {
  node_name = var.environment
  name      = var.node_config.vlan_name
  address   = var.node_config.vlan_address
  gateway   = var.node_config.vlan_gateway
  comment   = "VLAN 20 for IOT"
}

#Config VMs
resource "proxmox_virtual_environment_file" "cloud_config" {
  for_each = { for k, v in var.vm_config : k => v if try(v.enable_cloud_init, false) }

  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.environment
  source_raw {
    data = <<-EOF
    #cloud-config
    #password id an output from mkpasswd --method=SHA-512 --rounds=4096
    users:
      - name: ubuntu
        sudo: [sudo]
        shell: /bin/bash
        lock_passwd: false
        passwd: "{{ ubuntu_password | password_hash('sha512') }}"
        ssh_authorized_keys:
          - "${var.ubuntu_docker_ssh_pub}"

    package_update: true
    package_upgrade: true
    packages:
      - docker.io
      - docker-compose
      - git
      - curl

    runcmd:
      - systemctl enable docker
      - systemctl start docker
      - usermod -aG docker ubuntu
      - curl -L https://downloads.portainer.io/ce2-20/portainer-agent-stack.yml -o /home/ubuntu/portainer-agent-stack.yml
    EOF

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
