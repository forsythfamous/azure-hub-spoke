# Remote state in an Azure Storage blob, authenticated with Entra ID / OIDC
# (no storage account keys, no client secrets). Partial configuration: the
# values come from -backend-config (backend.hcl locally, repository
# variables in CI). Validation runs with `terraform init -backend=false`.
terraform {
  backend "azurerm" {}
}
