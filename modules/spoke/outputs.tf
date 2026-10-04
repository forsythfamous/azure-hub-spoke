output "vnet_id" {
  description = "Spoke VNet ID."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Spoke VNet name."
  value       = azurerm_virtual_network.this.name
}

output "subnet_ids" {
  description = "Subnet IDs keyed by subnet name."
  value       = { for k, s in azurerm_subnet.this : k => s.id }
}

output "nsg_ids" {
  description = "NSG IDs keyed by subnet name."
  value       = { for k, n in azurerm_network_security_group.this : k => n.id }
}

output "peering_ids" {
  description = "Peering IDs (spoke_to_hub, hub_to_spoke)."
  value = {
    spoke_to_hub = azurerm_virtual_network_peering.spoke_to_hub.id
    hub_to_spoke = azurerm_virtual_network_peering.hub_to_spoke.id
  }
}

output "route_table_id" {
  description = "Route table ID, or null when no subnet is routed via the firewall."
  value       = one(azurerm_route_table.this[*].id)
}

output "routed_subnet_names" {
  description = "Subnets whose default route points at the hub firewall."
  value       = sort(keys(local.routed_subnets))
}
