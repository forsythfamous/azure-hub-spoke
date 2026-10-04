# Every resource in the topology that exposes diagnostic categories sends
# logs (allLogs, or every category) and all platform metrics to one workspace.
# Not covered because Azure exposes no diagnostic settings for them: Private
# DNS zones, route tables, VNet peerings, WAF policies (their events surface
# in the Application Gateway firewall log).

module "monitoring" {
  source = "../../modules/monitoring"

  name                = local.names.log
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = local.tags

  diagnostic_targets = merge(
    {
      vnet-hub                   = { resource_id = module.hub.vnet_id }
      vnet-workload              = { resource_id = module.spoke_workload.vnet_id }
      vnet-data                  = { resource_id = module.spoke_data.vnet_id }
      nsg-hub-shared-services    = { resource_id = module.hub.nsg_ids["shared-services"] }
      nsg-workload-appgw         = { resource_id = module.spoke_workload.nsg_ids["snet-appgw"] }
      nsg-workload-app           = { resource_id = module.spoke_workload.nsg_ids["snet-app"] }
      nsg-data-private-endpoints = { resource_id = module.spoke_data.nsg_ids["snet-private-endpoints"] }
      pip-appgw                  = { resource_id = module.app_gateway.public_ip_id }
      appgw                      = { resource_id = module.app_gateway.id, dedicated = true }
      storage-account            = { resource_id = azurerm_storage_account.data.id }
      storage-blob               = { resource_id = "${azurerm_storage_account.data.id}/blobServices/default" }
    },
    var.deploy_backend_vm ? {
      vm-app = { resource_id = azurerm_linux_virtual_machine.app[0].id }
    } : {},
    var.enable_firewall ? {
      firewall     = { resource_id = module.hub.firewall_id, dedicated = true }
      pip-firewall = { resource_id = module.hub.firewall_public_ip_id }
    } : {},
  )
}
