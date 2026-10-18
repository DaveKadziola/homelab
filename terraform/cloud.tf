# HCP Terraform stores the state; Terraform itself runs locally (execution mode "local")
# on the self-hosted runner or the laptop. TF_WORKSPACE picks the workspace:
#   homelab      - prod (infra-plan.yml, infra-apply-prod.yml)
#   homelab-dev  - DEV  (infra-plan-dev.yml, infra-apply-dev.yml, utils/dev-apply-local.sh,
#                  tests/infra/run.sh)
terraform {
  cloud {
    organization = "dkhomelabserver"
  }
}
