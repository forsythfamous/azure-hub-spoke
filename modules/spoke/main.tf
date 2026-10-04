# A spoke VNet: subnets with one NSG each (explicit rules supplied by the
# caller), optional UDRs towards the hub firewall, bidirectional peering to
# the hub and links to the hub's Private DNS zones.

resource "azurerm_virtual_network" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  for_each = var.subnets

  name                              = each.key
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [each.value.address_prefix]
  default_outbound_access_enabled   = each.value.default_outbound_access_enabled
  private_endpoint_network_policies = each.value.private_endpoint_network_policies
}

# ---------------------------------------------------------------------------
# NSGs: one per subnet, rules passed in explicitly by the caller.
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "this" {
  for_each = var.subnets

  name                = "nsg-${var.name}-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  dynamic "security_rule" {
    for_each = each.value.nsg_rules
    content {
      name                         = security_rule.value.name
      priority                     = security_rule.value.priority
      direction                    = security_rule.value.direction
      access                       = security_rule.value.access
      protocol                     = security_rule.value.protocol
      source_port_range            = "*"
      destination_port_range       = length(security_rule.value.destination_ports) == 1 ? security_rule.value.destination_ports[0] : null
      destination_port_ranges      = length(security_rule.value.destination_ports) > 1 ? security_rule.value.destination_ports : null
      source_address_prefix        = length(security_rule.value.source_prefixes) == 1 ? security_rule.value.source_prefixes[0] : null
      source_address_prefixes      = length(security_rule.value.source_prefixes) > 1 ? security_rule.value.source_prefixes : null
      destination_address_prefix   = length(security_rule.value.destination_prefixes) == 1 ? security_rule.value.destination_prefixes[0] : null
      destination_address_prefixes = length(security_rule.value.destination_prefixes) > 1 ? security_rule.value.destination_prefixes : null
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each                  = var.subnets
  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}

# ---------------------------------------------------------------------------
# UDRs: only when the hub firewall exists. enable_firewall_routing is a plain
# bool so that count is known at plan time even before the firewall IP is.
# ---------------------------------------------------------------------------

locals {
  routed_subnets = var.enable_firewall_routing ? {
    for k, s in var.subnets : k => s if s.route_via_firewall
  } : {}
}

resource "azurerm_route_table" "this" {
  count = length(local.routed_subnets) > 0 ? 1 : 0

  name                          = "rt-${var.name}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = false
  tags                          = var.tags

  route {
    name                   = "default-via-hub-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }
}

resource "azurerm_subnet_route_table_association" "this" {
  for_each       = local.routed_subnets
  subnet_id      = azurerm_subnet.this[each.key].id
  route_table_id = azurerm_route_table.this[0].id
}

# ---------------------------------------------------------------------------
# Peering (both directions are owned by the spoke so that adding a spoke
# never requires editing the hub).
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "peer-${var.name}-to-hub"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.this.name
  remote_virtual_network_id    = var.hub_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true # traffic forwarded by the hub firewall
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "peer-hub-to-${var.name}"
  resource_group_name          = var.hub_resource_group_name
  virtual_network_name         = var.hub_vnet_name
  remote_virtual_network_id    = azurerm_virtual_network.this.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
}

# ---------------------------------------------------------------------------
# Private DNS: link this spoke to every zone hosted in the hub.
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = toset(var.private_dns_zone_names)

  name                  = "link-${var.name}"
  resource_group_name   = var.private_dns_zone_resource_group_name
  private_dns_zone_name = each.value
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}
