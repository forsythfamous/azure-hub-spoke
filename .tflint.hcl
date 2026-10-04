config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

rule "terraform_naming_convention" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

# The dev environment is built for deploy -> verify -> destroy cycles and the
# destroy workflow must be able to remove the storage account. Re-enable this
# rule (and add prevent_destroy) for any environment that holds real data.
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}
