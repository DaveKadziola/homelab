# terraform

Creates the Proxmox guests. State is in HCP Terraform, not in this directory. `environments/dev/terraform.tfstate` and `plan.tfplan`, if present on a laptop, are local leftovers and are not the state CI uses.

| File | Does |
| --- | --- |
| `main.tf` | The guests and the cloud-init drive |
| `variables.tf` | Inputs. The environment picks the rest |
| `cloud.tf` | HCP Terraform org and workspace |
| `providers.tf` | The Proxmox provider |
| `versions.tf` | Terraform and provider versions |
| `cloud-init-user-data.yaml.tpl` | First boot of a guest |
| `environments/dev/terraform.tfvars` | Nested Proxmox on the laptop. Workspace `homelab-dev` |
| `environments/prod/terraform.tfvars` | Physical host. Workspace `homelab` |

A push to `homelab-v2` applies the dev workspace. A push to `main` applies prod only after the prod approval. `utils/dev-apply-local.sh` applies dev from the laptop and races that push. `utils/tf-plan-risk.py` reads a prod plan and says whether it must stop for a second approval.
