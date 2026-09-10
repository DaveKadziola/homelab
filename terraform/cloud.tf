# Prod CI uses HCP Terraform (workspace homelab).
# Local / GHA dev apply: rename this file aside or use TF_DATA_DIR with
# utils/dev-apply-local.sh which disables the cloud block temporarily.
terraform {
  cloud {
    organization = "dkhomelabserver"
    workspaces {
      name = "homelab"
    }
  }
}
