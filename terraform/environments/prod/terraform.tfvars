node_config = {
  cert_setup_enabled = true
  vlan_name          = "vmbr0.20"
  vlan_address       = "192.168.20.20/24"
  vlan_gateway       = "192.168.20.1"
  bridge_name        = "vmbr0"
  bridge_ports       = ["enp1s0"]
  bridge_vlan_aware  = true
  dns_domain         = "router.dkhomelabserver.xyz"
  dns_servers        = ["192.168.20.1"]
}

vm_config = {
  homeassistant = {
    vm_id             = 100
    vm_name           = "home-assistant"
    vm_description    = "Home Assistant OS managed by Terraform"
    vm_tags           = ["homeassistant", "terraform"]
    bios              = "ovmf"
    ram               = 6144
    cpu_cores         = 2
    net_dev_type      = "vmbr0"
    vlan_tag          = 20
    enable_cloud_init = false
    efi_disk_size     = "4m"
    storage_type      = "local-lvm"
    storage_interface = "scsi0"
    storage_size      = 45
    ssd_enabled       = true
    boot_order        = ["scsi0"]
    image_url         = "https://github.com/DaveKadziola/homelab/releases/download/HomeAssistantImages/haos_ova-15.2.qcow2.img"
    img_file_format   = "qcow2"
    img_storage_type  = "local"
  }

  docker = {
    vm_id              = 101
    vm_name            = "ubuntu-docker"
    vm_description     = "Ubuntu for Docker containers managed by Terraform"
    vm_tags            = ["docker", "ubuntu-server", "cloud-init", "terraform"]
    bios               = "seabios"
    ram                = 4096
    cpu_cores          = 1
    net_dev_type       = "vmbr0"
    vlan_tag           = 20
    enable_cloud_init  = true
    cloud_init_cidr    = "192.168.20.21/24"
    cloud_init_gateway = "192.168.20.1"
    cloud_init_dns     = "192.168.20.1"
    storage_type       = "local-lvm"
    storage_interface  = "scsi0"
    storage_size       = 25
    ssd_enabled        = true
    image_url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    img_file_format    = "qcow2"
    img_storage_type   = "local"
  }
}