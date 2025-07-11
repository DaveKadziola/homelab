node_config = {
  cert_setup_enabled = false
  vlan_name          = "vmbr0.20"
  bridge_name        = "vmbr0"
  bridge_address     = "192.168.122.219/24"
  bridge_gateway     = "192.168.122.1"
  bridge_ports       = ["enp8s0"]
  bridge_vlan_aware  = false
  dns_domain         = "homelabdev"
  dns_servers        = ["192.168.1.1"]
}

vm_config = {
  homeassistant = {
    vm_id             = 100
    vm_name           = "home-assistant"
    vm_description    = "Home Assistant OS managed by Terraform"
    vm_tags           = ["homeassistant", "terraform"]
    bios              = "ovmf"
    ram               = 4096
    cpu_cores         = 2
    net_dev_type      = "vmbr0"
    enable_cloud_init = false
    efi_disk_size     = "4m"
    storage_type      = "local-lvm"
    storage_interface = "scsi0"
    storage_size      = 32
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
    ram                = 1024
    cpu_cores          = 1
    net_dev_type       = "vmbr0"
    enable_cloud_init  = true
    cloud_init_cidr    = "192.168.122.221/24"
    cloud_init_gateway = "192.168.122.1"
    cloud_init_dns     = "8.8.8.8"
    storage_type       = "local-lvm"
    storage_interface  = "scsi0"
    storage_size       = 10
    ssd_enabled        = true
    image_url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    img_file_format    = "qcow2"
    img_storage_type   = "local"
  }
}