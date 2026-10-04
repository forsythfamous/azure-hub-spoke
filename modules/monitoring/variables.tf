variable "name" {
  description = "Log Analytics workspace name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the workspace."
  type        = string
}

variable "retention_in_days" {
  description = "Interactive retention. 30 days is included in the ingestion price."
  type        = number
  default     = 30

  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "retention_in_days must be between 30 and 730."
  }
}

variable "daily_quota_gb" {
  description = "Daily ingestion cap in GB (-1 = unlimited). Keeps a misbehaving log source from running up the bill."
  type        = number
  default     = 1
}

variable "diagnostic_targets" {
  description = <<-EOT
    Resources to attach diagnostic settings to. Keys must be static strings
    (they become for_each keys); values may be unknown until apply.
    Set dedicated = true for resource types that support resource-specific
    tables (Application Gateway, Azure Firewall).
  EOT
  type = map(object({
    resource_id = string
    dedicated   = optional(bool, false)
  }))
  default = {}
}

variable "tags" {
  description = "Tags applied to the workspace."
  type        = map(string)
  default     = {}
}
