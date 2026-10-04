output "vnet_id" {
  description = "Hub VNet ID."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Hub VNet name."
  value       = azurerm_virtual_network.this.name
}

output "nsg_ids" {
  description = "NSG IDs in the hub, keyed by subnet role."
  value       = { shared-services = azurerm_network_security_group.shared.id }
}

output "private_dns_zone_ids" {
  description = "Private DNS zone IDs keyed by zone name."
  value       = { for k, z in azurerm_private_dns_zone.this : k => z.id }
}

output "firewall_name" {
  description = "Azure Firewall name, or null when disabled (known at plan time)."
  value       = one(azurerm_firewall.this[*].name)
}

output "firewall_id" {
  description = "Azure Firewall ID, or null when disabled."
  value       = one(azurerm_firewall.this[*].id)
}

output "firewall_private_ip" {
  description = "Firewall private IP (UDR next hop), or null when disabled."
  value       = one(azurerm_firewall.this[*].ip_configuration[0].private_ip_address)
}

output "firewall_public_ip_id" {
  description = "Firewall public IP resource ID, or null when disabled."
  value       = one(azurerm_public_ip.firewall[*].id)
}

output "firewall_subnet_prefix" {
  description = "AzureFirewallSubnet CIDR (source of SNAT'd traffic)."
  value       = var.firewall_subnet_prefix
}
