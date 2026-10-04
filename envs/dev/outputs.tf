# Outputs are what docs/VERIFY.md consumes (`terraform output -raw <name>`).

output "resource_groups" {
  description = "Resource group names."
  value = {
    hub      = azurerm_resource_group.hub.name
    workload = azurerm_resource_group.workload.name
    data     = azurerm_resource_group.data.name
  }
}

output "vnet_names" {
  description = "VNet names."
  value = {
    hub      = module.hub.vnet_name
    workload = module.spoke_workload.vnet_name
    data     = module.spoke_data.vnet_name
  }
}

output "app_gateway_public_ip" {
  description = "Public IP of the WAF-protected listener."
  value       = module.app_gateway.public_ip_address
}

output "app_gateway_fqdn" {
  description = "Public FQDN of the listener (null without app_gateway_dns_label)."
  value       = module.app_gateway.fqdn
}

output "storage_account_name" {
  description = "Storage account reachable only through its private endpoint."
  value       = azurerm_storage_account.data.name
}

output "storage_blob_host" {
  description = "Public blob hostname; resolves to the private endpoint from linked VNets."
  value       = azurerm_storage_account.data.primary_blob_host
}

output "storage_private_endpoint_ip" {
  description = "Private IP of the blob private endpoint."
  value       = module.pe_storage_blob.private_ip_address
}

output "backend_vm_name" {
  description = "Backend VM name (null when not deployed)."
  value       = one(azurerm_linux_virtual_machine.app[*].name)
}

output "firewall_private_ip" {
  description = "Hub firewall private IP (null when disabled)."
  value       = module.hub.firewall_private_ip
}

output "log_analytics_workspace_id" {
  description = "Workspace GUID for `az monitor log-analytics query --workspace`."
  value       = module.monitoring.workspace_customer_id
}
