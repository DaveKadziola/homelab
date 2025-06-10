vm_config = {
  homeassistant = {
    vm_id             = 100
    vm_name           = "home-assistant"
    vm_description    = "Home Assistant OS managed by Terraform"
    vm_tags           = ["homeassistant", "terraform"]
    ram               = 8192
    cpu_cores         = 2
    net_dev_type      = "vmbr0"
    cidr              = "192.168.20.11/24"
    gateway           = "192.168.20.1"
    dns               = "192.168.1.1"
    storage_type      = "local"
    storage_interface = "virtio0"
    storage_size      = 45
    file_format       = "qcow2"
    image_url         = "https://github.com/DaveKadziola/homelab/releases/download/HomeAssistantImages/haos_ova-15.2.qcow2.img"
  }

docker = {
    vm_id             = 101
    vm_name           = "ubuntu-docker"
    vm_description    = "Ubuntu Server for Docker containers managed by Terraform"
    vm_tags           = ["docker", "ubuntu-server", "cloud-init", "terraform" ]
    ram               = 4096
    cpu_cores         = 1
    net_dev_type      = "vmbr0"
    cidr              = "192.168.20.12/24"
    gateway           = "192.168.20.1"
    dns               = "192.168.1.1"
    storage_type      = "local"
    storage_interface = "virtio0"
    storage_size      = 25
    file_format       = "qcow2"
    image_url         = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  }
}