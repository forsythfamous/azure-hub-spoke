# Workload tier: one small Linux VM behind the Application Gateway. It is
# the backend for the WAF and the in-VNet vantage point for docs/VERIFY.md
# (reached with `az vm run-command`, so it has no public IP and no SSH rule).

# AZU-0068: traffic is filtered by the subnet NSG (snet-app); a second NSG on
# the NIC would duplicate the rule set without adding control.
#trivy:ignore:AVD-AZU-0068
resource "azurerm_network_interface" "app" {
  count               = var.deploy_backend_vm ? 1 : 0
  name                = "nic-${local.names.vm_app}"
  location            = var.location
  resource_group_name = azurerm_resource_group.workload.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = module.spoke_workload.subnet_ids["snet-app"]
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "app" {
  # Extensions stay enabled: Run Command is the access path used by
  # docs/VERIFY.md (no SSH rule, no Bastion). Encryption at host needs the
  # EncryptionAtHost subscription feature, hence the variable.
  count = var.deploy_backend_vm ? 1 : 0

  name                            = local.names.vm_app
  location                        = var.location
  resource_group_name             = azurerm_resource_group.workload.name
  size                            = var.vm_size
  zone                            = length(var.zones) > 0 ? var.zones[0] : null
  admin_username                  = var.vm_admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.app[0].id]
  custom_data                     = base64encode(file("${path.module}/cloud-init.yaml"))
  allow_extension_operations      = true
  encryption_at_host_enabled      = var.vm_encryption_at_host
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  patch_mode                      = "AutomaticByPlatform"
  patch_assessment_mode           = "AutomaticByPlatform"
  tags                            = local.tags

  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = var.vm_admin_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # Managed boot diagnostics storage (serial console as a break-glass path).
  boot_diagnostics {}

  lifecycle {
    precondition {
      condition     = var.vm_admin_ssh_public_key != null
      error_message = "vm_admin_ssh_public_key is required when deploy_backend_vm is true."
    }
  }
}

module "app_gateway" {
  source = "../../modules/app-gateway-waf"

  name                = local.names.appgw
  waf_policy_name     = local.names.waf_policy
  location            = var.location
  resource_group_name = azurerm_resource_group.workload.name
  subnet_id           = module.spoke_workload.subnet_ids["snet-appgw"]
  zones               = var.zones
  dns_label           = var.app_gateway_dns_label

  backend_ip_addresses = azurerm_network_interface.app[*].private_ip_address

  waf_mode             = var.waf_mode
  admin_allowed_cidrs  = var.waf_admin_allowed_cidrs
  rate_limit_threshold = var.waf_rate_limit_threshold

  tags = local.tags
}
