# Proxmox prod — homelab v2 (as-built: host .20.20, NAS .20.12, apps .50.30)
# NIC1: vmbr0 vlan-aware (IOT mgmt + tag 20). NIC2: disk passthrough to NAS VM. NIC3: APP trunk tag 51.

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
  nas = {
    vm_id              = 102
    vm_name            = "ubuntu-nas"
    vm_description     = "NAS VM — NFS, SA500/Purple passthrough (NIC2)"
    vm_tags            = ["nas", "ubuntu-server", "cloud-init", "terraform"]
    bios               = "seabios"
    ram                = 4096
    cpu_cores          = 2
    net_dev_type       = "vmbr0"
    vlan_tag           = 20
    enable_cloud_init  = true
    docker_enabled     = false
    cloud_init_cidr    = "192.168.20.12/24"
    cloud_init_gateway = "192.168.20.1"
    cloud_init_dns     = "192.168.20.1"
    storage_type       = "local-lvm"
    storage_interface  = "scsi0"
    storage_size       = 32
    ssd_enabled        = true
    image_url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    img_file_format    = "qcow2"
    img_storage_type   = "local"
  }

  apps = {
    vm_id              = 101
    vm_name            = "ubuntu-apps"
    vm_description     = "Docker / core stack — APP VLAN 51"
    vm_tags            = ["docker", "ubuntu-server", "cloud-init", "terraform"]
    bios               = "seabios"
    ram                = 8192
    cpu_cores          = 2
    net_dev_type       = "vmbr0"
    vlan_tag           = 51
    enable_cloud_init  = true
    cloud_init_cidr    = "192.168.50.30/26"
    cloud_init_gateway = "192.168.50.50"
    cloud_init_dns     = "192.168.20.1"
    storage_type       = "local-lvm"
    storage_interface  = "scsi0"
    storage_size       = 32
    ssd_enabled        = true
    image_url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    img_file_format    = "qcow2"
    img_storage_type   = "local"
  }
}
