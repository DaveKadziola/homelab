vm_config = {
  homeassistant = {
    vm_id             = 100
    vm_name           = "home-assistant"
    vm_description    = "Home Assistant OS managed by Terraform"
    vm_tags           = ["homeassistant", "terraform"]
    bios              = "ovmf"
    ram               = 8192
    cpu_cores         = 2
    net_dev_type      = "vmbr0"
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
    enable_cloud_init  = false
    cloud_init_cidr    = "192.168.20.12/24"
    cloud_init_gateway = "192.168.20.1"
    cloud_init_dns     = "192.168.1.1"
    storage_type       = "local-lvm"
    storage_interface  = "scsi0"
    storage_size       = 25
    ssd_enabled        = true
    image_url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    img_file_format    = "qcow2"
    img_storage_type   = "local"
  }
}