# Naming: <type>-<workload>-<environment>-<region>[-<role>], following the
# Cloud Adoption Framework abbreviations. Storage accounts cannot contain
# hyphens and must be globally unique, so they get a deterministic suffix
# derived from the subscription ID.

data "azurerm_client_config" "current" {}

locals {
  region_short = lookup({
    polandcentral      = "plc"
    westeurope         = "weu"
    northeurope        = "neu"
    swedencentral      = "sdc"
    germanywestcentral = "gwc"
    eastus             = "eus"
    eastus2            = "eus2"
  }, var.location, var.location)

  base = "${var.workload}-${var.environment}-${local.region_short}"

  storage_suffix = substr(md5("${data.azurerm_client_config.current.subscription_id}-${local.base}"), 0, 6)

  names = {
    rg_hub        = "rg-${local.base}-hub"
    rg_workload   = "rg-${local.base}-workload"
    rg_data       = "rg-${local.base}-data"
    vnet_hub      = "vnet-${local.base}-hub"
    vnet_workload = "vnet-${local.base}-workload"
    vnet_data     = "vnet-${local.base}-data"
    firewall      = "afw-${local.base}-hub"
    log           = "log-${local.base}"
    appgw         = "agw-${local.base}"
    waf_policy    = "waf-${local.base}"
    storage       = "st${var.workload}${var.environment}${local.storage_suffix}"
    vm_app        = "vm-${local.base}-app"
  }

  tags = merge(var.extra_tags, {
    workload    = var.workload
    environment = var.environment
    owner       = var.owner
    managed-by  = "terraform"
    repository  = var.repository
  })

  # ---------------------------------------------------------------------
  # Address plan. One /22 per VNet; nothing overlaps.
  # ---------------------------------------------------------------------
  address = {
    hub                = "10.10.0.0/22"
    hub_firewall       = "10.10.0.0/26"
    hub_firewall_mgmt  = "10.10.0.64/26"
    hub_shared         = "10.10.1.0/24"
    workload           = "10.11.0.0/22"
    workload_appgw     = "10.11.0.0/24"
    workload_app       = "10.11.1.0/24"
    data               = "10.12.0.0/22"
    data_private_links = "10.12.0.0/24"
  }

  private_dns_zones = [
    "privatelink.blob.core.windows.net",
    "privatelink.file.core.windows.net",
    "privatelink.vaultcore.azure.net",
  ]

  # Rule closing every NSG: makes the effective inbound policy explicit
  # instead of relying on Azure's AllowVnetInBound default (priority 65000).
  deny_all_inbound = {
    name            = "Deny-All-Inbound"
    priority        = 4096
    direction       = "Inbound"
    access          = "Deny"
    protocol        = "*"
    source_prefixes = ["*"]
  }
}
