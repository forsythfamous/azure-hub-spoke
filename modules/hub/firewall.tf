# Azure Firewall is the single most expensive component in this design and is
# therefore opt-in (ADR-0002). With it disabled, spokes are isolated from each
# other: there is no transit path, which is the secure default.

locals {
  firewall_basic = var.firewall_sku_tier == "Basic"
}

resource "azurerm_public_ip" "firewall" {
  count               = var.enable_firewall ? 1 : 0
  name                = "pip-${var.firewall_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones
  tags                = var.tags
}

resource "azurerm_public_ip" "firewall_management" {
  count               = var.enable_firewall && local.firewall_basic ? 1 : 0
  name                = "pip-${var.firewall_name}-mgmt"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones
  tags                = var.tags
}

resource "azurerm_firewall_policy" "this" {
  count               = var.enable_firewall ? 1 : 0
  name                = "afwp-${var.firewall_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.firewall_sku_tier

  # Basic supports threat intelligence in Alert mode only.
  threat_intelligence_mode = local.firewall_basic ? "Alert" : "Deny"

  tags = var.tags
}

resource "azurerm_firewall_policy_rule_collection_group" "this" {
  count              = var.enable_firewall ? 1 : 0
  name               = "rcg-hub-spoke"
  firewall_policy_id = azurerm_firewall_policy.this[0].id
  priority           = 200

  # Application rules SNAT through the firewall, which keeps the return path
  # from the private endpoint symmetric without extra UDRs in the data spoke.
  dynamic "application_rule_collection" {
    for_each = length(var.firewall_application_rules) > 0 ? [1] : []
    content {
      name     = "arc-allow"
      priority = 200
      action   = "Allow"

      dynamic "rule" {
        for_each = var.firewall_application_rules
        content {
          name              = rule.key
          source_addresses  = rule.value.source_addresses
          destination_fqdns = rule.value.destination_fqdns
          protocols {
            type = "Https"
            port = 443
          }
        }
      }
    }
  }

  dynamic "network_rule_collection" {
    for_each = length(var.firewall_network_rules) > 0 ? [1] : []
    content {
      name     = "nrc-allow"
      priority = 300
      action   = "Allow"

      dynamic "rule" {
        for_each = var.firewall_network_rules
        content {
          name                  = rule.key
          protocols             = rule.value.protocols
          source_addresses      = rule.value.source_addresses
          destination_addresses = rule.value.destination_addresses
          destination_ports     = rule.value.destination_ports
        }
      }
    }
  }
}

resource "azurerm_firewall" "this" {
  count               = var.enable_firewall ? 1 : 0
  name                = var.firewall_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "AZFW_VNet"
  sku_tier            = var.firewall_sku_tier
  firewall_policy_id  = azurerm_firewall_policy.this[0].id
  zones               = var.zones
  tags                = var.tags

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall[0].id
  }

  dynamic "management_ip_configuration" {
    for_each = local.firewall_basic ? [1] : []
    content {
      name                 = "mgmt-ipconfig"
      subnet_id            = azurerm_subnet.firewall_management.id
      public_ip_address_id = azurerm_public_ip.firewall_management[0].id
    }
  }

  depends_on = [azurerm_firewall_policy_rule_collection_group.this]
}
