# Proxmox prod — homelab v2 (as-built: host .20.20, NAS .20.12, apps .50.30)
# vmbr0 vlan-aware on bond0 (active-backup nic1 Intel + nic0 Realtek); mgmt on vmbr0.20 (switch delivers IOT tagged 20).
# vmbr1 vlan-aware on nic2 (Intel) for APP: VLAN 51 tagged on the switch port (ARP-tested 2026-10-19).
# Host network: config/pve/interfaces.prod, written by utils/pve-network.py - TF does not manage it (manage_node_network = false).

proxmox_node_name   = "proxmox"
manage_node_network = false

node_config = {
  cert_setup_enabled = false
  vlan_name          = "vmbr0.20"
  vlan_address       = "192.168.20.20/24"
  vlan_gateway       = "192.168.20.1"
  bridge_name        = "vmbr0"
  bridge_ports       = ["bond0"]
  bridge_vlan_aware  = true
  dns_domain         = "router.dkhomelabserver.xyz"
  dns_servers        = ["192.168.20.1"]
}

vm_config = {
  nas = {
    vm_id              = 102
    vm_name            = "ubuntu-nas"
    startup_order      = 1
    startup_up_delay   = 60
    vm_description     = "NAS VM — NFS, SA500/Purple disk passthrough (by-id)"
    vm_tags            = ["nas", "ubuntu-server", "cloud-init", "terraform"]
    bios               = "seabios"
    ram                = 2048 # was 4096; processes used ~0.5 GiB (2026-10-23)
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
    vm_id          = 101
    vm_name        = "ubuntu-apps"
    startup_order  = 2
    vm_description = "Docker / core stack — APP VLAN 51"
    vm_tags        = ["docker", "ubuntu-server", "cloud-init", "terraform"]
    bios           = "seabios"
    ram            = 9216
    cpu_cores      = 2
    # Immich machine-learning needs x86-64-v2 (NumPy) — kvm64 crashes.
    cpu_type           = "host"
    net_dev_type       = "vmbr1"
    vlan_tag           = 51
    enable_cloud_init  = true
    cloud_init_cidr    = "192.168.50.30/26"
    cloud_init_gateway = "192.168.50.50"
    cloud_init_dns     = "192.168.50.50" # own gateway: AdGuard answers .20.1 from .50.50 over UDP
    storage_type       = "local-lvm"
    storage_interface  = "scsi0"
    # Full P0–P2 image set needed 27G on dev (media libs live on NFS, not here).
    storage_size     = 48
    ssd_enabled      = true
    image_url        = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    img_file_format  = "qcow2"
    img_storage_type = "local"
  }
}
