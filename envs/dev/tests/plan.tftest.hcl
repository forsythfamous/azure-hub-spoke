# Offline plan tests with a mocked azurerm provider: no Azure credentials,
# no API calls. They exercise the real configuration graph (for_each keys,
# conditionals, cross-module wiring) and pin the security-relevant toggles.
# Run: terraform init -backend=false && terraform test

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
      tenant_id       = "00000000-0000-0000-0000-000000000000"
    }
  }

  mock_data "azurerm_monitor_diagnostic_categories" {
    defaults = {
      log_category_groups = ["allLogs", "audit"]
      log_category_types  = ["ExampleLog"]
      metrics             = ["AllMetrics"]
    }
  }
}

variables {
  # Public half of a throwaway key generated for these tests; the private key
  # was discarded. The provider parses the key format at plan time.
  owner                   = "platform-team"
  vm_admin_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIANI9AxhGV2mCQCWytvo0ArAe5Z9UFhM7oyEsQY67j5 test@example"
  budget_contact_emails   = ["ops@example.com"]
}

run "default_firewall_off" {
  command = plan

  assert {
    condition     = module.hub.firewall_name == null
    error_message = "Firewall must not be deployed by default."
  }

  assert {
    condition     = length(module.spoke_workload.routed_subnet_names) == 0 && length(module.spoke_data.routed_subnet_names) == 0
    error_message = "No UDRs may exist without a firewall to route to."
  }

  assert {
    condition     = length(module.spoke_workload.peering_ids) == 2 && length(module.spoke_data.peering_ids) == 2
    error_message = "Each spoke must own both directions of its hub peering."
  }

  assert {
    condition     = azurerm_storage_account.data.public_network_access_enabled == false && azurerm_storage_account.data.shared_access_key_enabled == false
    error_message = "Storage must have public network access and shared keys disabled."
  }

  assert {
    condition     = length(module.monitoring.workspace_name) > 0 && length(azurerm_consumption_budget_resource_group.this) == 3
    error_message = "Monitoring workspace and one budget per resource group are expected."
  }

  assert {
    condition     = startswith(local.names.storage, "sthubspokedev") && length(local.names.storage) <= 24
    error_message = "Storage account name must follow the convention and fit 24 characters."
  }
}

run "firewall_on_adds_routing" {
  command = plan

  variables {
    enable_firewall = true
  }

  assert {
    condition     = module.hub.firewall_name == "afw-hubspoke-dev-plc-hub"
    error_message = "Firewall must be deployed when enable_firewall = true."
  }

  assert {
    condition     = join(",", module.spoke_workload.routed_subnet_names) == "snet-app"
    error_message = "Only the app subnet may be routed via the firewall (never the Application Gateway subnet)."
  }

  assert {
    condition     = length(module.spoke_data.routed_subnet_names) == 0
    error_message = "The data spoke needs no UDR (application rules SNAT, keeping the return path symmetric)."
  }
}

run "rejects_bad_workload_name" {
  command = plan

  variables {
    workload = "Hub-Spoke"
  }

  expect_failures = [var.workload]
}
