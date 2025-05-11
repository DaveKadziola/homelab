vm_config = {
  homeassistant = {
    cores     = 2
    memory    = 6144
    ip        = "192.168.100.101/24"
    storage   = "ssd-lvm"
    vm_id     = 200
    image_url = "https://github.com/home-assistant/operating-system/releases/download/15.2/haos_ova-15.2.qcow2.xz"
  }
  docker = {
    cores   = 2
    memory  = 6144
    ip      = "192.168.100.102/24"
    storage = "ssd-lvm"
    vm_id   = 201
  }
}
