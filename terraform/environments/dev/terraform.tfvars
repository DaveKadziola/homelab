# Dev — nested Proxmox on laptop (libvirt VM "Proxmox"), same TF module as prod.
# API: https://<nested-ip>:8006 — set via utils/bootstrap-dev-proxmox.sh
# State: local (infra-*-dev.yml uses init -backend=false).

# Nested PVE UI title is "dev" — hostname/node name, not "pve"
proxmox_node_name   = "dev"
manage_node_network = false

node_config = {
  cert_setup_enabled = false
  vlan_name          = "vmbr0"
  bridge_name        = "vmbr0"
  bridge_vlan_aware  = false
  dns_domain         = "homelabdev.local"
  dns_servers        = ["192.168.122.1"]
}

vm_config = {
  apps = {
    vm_id          = 101
    vm_name        = "ubuntu-apps"
    vm_description = "Dev Docker stack — nested Proxmox"
    vm_tags        = ["docker", "ubuntu-server", "cloud-init", "terraform", "dev"]
    bios           = "seabios"
    # Nested PVE has ~8 GiB; HA-dev kept at 2 GiB so apps can use 6 GiB for full P0–P2 stack.
    ram                = 6144
    cpu_cores          = 2
    net_dev_type       = "vmbr0"
    enable_cloud_init  = true
    docker_enabled     = true
    cloud_init_cidr    = "192.168.122.50/24"
    cloud_init_gateway = "192.168.122.1"
    cloud_init_dns     = "192.168.122.1"
    storage_type       = "local-lvm"
    storage_interface  = "scsi0"
    # Immich+Jellyfin+P0–P2 images need >16G; resized live to 27G on nested PVE (local-lvm headroom).
    storage_size     = 27
    ssd_enabled      = true
    image_url        = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    img_file_format  = "qcow2"
    img_storage_type = "local"
  }
}
