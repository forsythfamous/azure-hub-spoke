output "id" {
  description = "Application Gateway ID."
  value       = azurerm_application_gateway.this.id
}

output "public_ip_id" {
  description = "Public IP resource ID."
  value       = azurerm_public_ip.this.id
}

output "public_ip_address" {
  description = "Public IP address of the listener."
  value       = azurerm_public_ip.this.ip_address
}

output "fqdn" {
  description = "Public FQDN, when dns_label is set."
  value       = azurerm_public_ip.this.fqdn
}

output "waf_policy_id" {
  description = "WAF policy ID."
  value       = azurerm_web_application_firewall_policy.this.id
}
