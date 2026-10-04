# Storage account reachable only through its private endpoint in the data
# spoke. No public network path, no shared keys, Entra ID authorization only.

#
# Accepted scanner findings (rationale, then the suppression):
# - AZU-0060 CMK: platform-managed keys + infrastructure (double) encryption
#   are the baseline here; CMK adds a Key Vault, identity and key rotation.
# - AZU-0058 GRS: LRS is a deliberate dev cost choice; production should set
#   storage_replication_type = "GZRS".
# - AZU-0057 logging: the check targets classic queue logging (data plane);
#   blob logs go to Log Analytics through diagnostic settings (monitoring.tf).
#trivy:ignore:AVD-AZU-0060
#trivy:ignore:AVD-AZU-0058
#trivy:ignore:AVD-AZU-0057
resource "azurerm_storage_account" "data" {
  name                     = local.names.storage
  location                 = var.location
  resource_group_name      = azurerm_resource_group.data.name
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type
  access_tier              = "Hot"

  public_network_access_enabled     = false
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  allow_nested_items_to_be_public   = false
  infrastructure_encryption_enabled = true
  cross_tenant_replication_enabled  = false
  local_user_enabled                = false
  sftp_enabled                      = false

  # AZU-0010 (trusted-services bypass) is intentionally not satisfied: with
  # public network access disabled the only path in is the private endpoint.
  #trivy:ignore:AVD-AZU-0010
  network_rules {
    default_action = "Deny"
    bypass         = ["None"]
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  sas_policy {
    expiration_period = "00.01:00:00"
    expiration_action = "Log"
  }

  tags = local.tags
}

# Created through ARM (storage_account_id), not the blob data plane, which
# is unreachable from outside the VNet by design.
resource "azurerm_storage_container" "data" {
  name                  = "data"
  storage_account_id    = azurerm_storage_account.data.id
  container_access_type = "private"
}

module "pe_storage_blob" {
  source = "../../modules/private-endpoint"

  name                 = "pe-${local.names.storage}-blob"
  location             = var.location
  resource_group_name  = azurerm_resource_group.data.name
  subnet_id            = module.spoke_data.subnet_ids["snet-private-endpoints"]
  target_resource_id   = azurerm_storage_account.data.id
  subresource_name     = "blob"
  private_dns_zone_ids = [module.hub.private_dns_zone_ids["privatelink.blob.core.windows.net"]]
  tags                 = local.tags
}
