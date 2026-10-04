provider "azurerm" {
  # Falls back to ARM_SUBSCRIPTION_ID when null (the CI path).
  subscription_id = var.subscription_id

  # Data-plane calls (if any) authenticate with Entra ID, never account keys.
  storage_use_azuread = true

  # The deployment identity is not granted subscription-wide provider
  # registration rights; register the providers once out of band (README).
  resource_provider_registrations = "none"

  features {
    storage {
      # The storage account has public network access disabled, so the CI
      # runner cannot reach its data plane. Manage it through ARM only.
      data_plane_available = false
    }

    log_analytics_workspace {
      # Deploy/verify/destroy cycles must be able to reuse the name.
      permanently_delete_on_destroy = true
    }
  }
}
