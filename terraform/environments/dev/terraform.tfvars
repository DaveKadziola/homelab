vm_config = {
  homeassistant = {
    cores     = 1
    memory    = 3072
    ip        = "192.168.122.220/24"
    storage   = "local-lvm"
    vm_id     = 100
    image_url = "https://github.com/home-assistant/operating-system/releases/download/15.2/haos_ova-15.2.qcow2.xz"
  }
  docker = {
    cores   = 1
    memory  = 1024
    ip      = "192.168.122.221/24"
    storage = "local-lvm"
    vm_id   = 101
  }
}
