# Hub VNet: shared services, the (optional) Azure Firewall and the
# Private DNS zones that every VNet in the topology resolves against.

resource "azurerm_virtual_network" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.address_space]
  tags                = var.tags
}

# The firewall subnets are always created: an empty subnet costs nothing and
# keeps the address plan stable when the firewall is toggled on later.
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet" # name mandated by Azure
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.firewall_subnet_prefix]
}

resource "azurerm_subnet" "firewall_management" {
  name                 = "AzureFirewallManagementSubnet" # required by the Basic SKU
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.firewall_management_subnet_prefix]
}

resource "azurerm_subnet" "shared" {
  name                            = "snet-shared-services"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.shared_subnet_prefix]
  default_outbound_access_enabled = false
}

resource "azurerm_network_security_group" "shared" {
  name                = "nsg-${var.name}-shared-services"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Nothing runs here yet; only intra-VNet traffic from the address plan is
  # allowed in, everything else is denied explicitly ahead of Azure's
  # permissive VirtualNetwork default rule.
  security_rule {
    name                       = "Allow-Spokes-Inbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443"]
    source_address_prefixes    = var.trusted_address_prefixes
    destination_address_prefix = var.shared_subnet_prefix
  }

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "shared" {
  subnet_id                 = azurerm_subnet.shared.id
  network_security_group_id = azurerm_network_security_group.shared.id
}
