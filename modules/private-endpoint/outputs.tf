output "id" {
  description = "Private endpoint ID."
  value       = azurerm_private_endpoint.this.id
}

output "private_ip_address" {
  description = "Private IP allocated to the endpoint NIC."
  value       = azurerm_private_endpoint.this.private_service_connection[0].private_ip_address
}

output "network_interface_id" {
  description = "ID of the endpoint's network interface."
  value       = azurerm_private_endpoint.this.network_interface[0].id
}
