# Central Log Analytics workspace plus diagnostic settings for every target
# passed in. Categories are discovered per resource at plan time, so a new
# log category on a resource type is picked up without code changes.

resource "azurerm_log_analytics_workspace" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_in_days

  # Cost guard: ingestion stops for the day once the cap is hit.
  # -1 disables the cap.
  daily_quota_gb = var.daily_quota_gb

  # Queries and ingestion through Entra ID only; no shared-key access.
  local_authentication_enabled = false

  tags = var.tags
}

data "azurerm_monitor_diagnostic_categories" "this" {
  for_each    = var.diagnostic_targets
  resource_id = each.value.resource_id
}

locals {
  # Diagnostic settings on the workspace itself (audit of queries).
  targets = merge(var.diagnostic_targets, {
    log-analytics = {
      resource_id = azurerm_log_analytics_workspace.this.id
      dedicated   = false
    }
  })

  categories = merge(
    { for k, v in data.azurerm_monitor_diagnostic_categories.this : k => v },
    { log-analytics = data.azurerm_monitor_diagnostic_categories.self },
  )
}

data "azurerm_monitor_diagnostic_categories" "self" {
  resource_id = azurerm_log_analytics_workspace.this.id
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = local.targets

  name                       = "diag-to-${var.name}"
  target_resource_id         = each.value.resource_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  # Resource-specific tables (e.g. AGWFirewallLogs, AZFWApplicationRule)
  # where the resource type supports them; AzureDiagnostics otherwise.
  log_analytics_destination_type = each.value.dedicated ? "Dedicated" : null

  dynamic "enabled_log" {
    # Prefer the allLogs category group; fall back to explicit categories
    # for resource types that do not expose category groups.
    for_each = (
      contains(local.categories[each.key].log_category_groups, "allLogs")
      ? [{ category = null, category_group = "allLogs" }]
      : [for c in local.categories[each.key].log_category_types : { category = c, category_group = null }]
    )
    content {
      category       = enabled_log.value.category
      category_group = enabled_log.value.category_group
    }
  }

  # Every metric category the resource exposes: usually "AllMetrics", but
  # e.g. storage accounts expose "Transaction" and "Capacity" instead.
  dynamic "enabled_metric" {
    for_each = local.categories[each.key].metrics
    content {
      category = enabled_metric.value
    }
  }
}
