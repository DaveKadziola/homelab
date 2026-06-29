terraform {
  required_version = ">= 1.8.0"

  cloud {
    organization = "dkhomelabserver"
    workspaces {
      name = "homelab"
    }
  }

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.77.1"
    }
  }
}
