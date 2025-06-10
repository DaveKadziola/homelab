terraform {
  backend "local" {
    path = "$HOME/HomeLab/git/actions-runner/terraform/states/${var.environment}/terraform.tfstate"
  }
}