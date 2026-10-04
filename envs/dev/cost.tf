# Budgets alert; they do not stop spend. Thresholds are sized for short
# deploy -> verify -> destroy cycles, so a forgotten environment is noticed
# within days, not at the end of the month.

locals {
  budget_scopes = {
    hub      = azurerm_resource_group.hub.id
    workload = azurerm_resource_group.workload.id
    data     = azurerm_resource_group.data.id
  }
}

resource "azurerm_consumption_budget_resource_group" "this" {
  for_each = local.budget_scopes

  name              = "budget-${local.base}-${each.key}"
  resource_group_id = each.value
  amount            = var.monthly_budgets[each.key]
  time_grain        = "Monthly"

  time_period {
    # Budgets must start on the first day of a month.
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", plantimestamp())
  }

  notification {
    enabled        = true
    operator       = "GreaterThanOrEqualTo"
    threshold      = 50
    threshold_type = "Actual"
    contact_emails = var.budget_contact_emails
  }

  notification {
    enabled        = true
    operator       = "GreaterThanOrEqualTo"
    threshold      = 100
    threshold_type = "Forecasted"
    contact_emails = var.budget_contact_emails
  }

  lifecycle {
    # start_date is evaluated once; it must not drift on every plan.
    ignore_changes = [time_period]
  }
}
