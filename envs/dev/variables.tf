# --- Context -----------------------------------------------------------------

variable "subscription_id" {
  description = "Target subscription. Leave null to use ARM_SUBSCRIPTION_ID (CI)."
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region for every resource."
  type        = string
  default     = "polandcentral"
}

variable "zones" {
  description = "Availability zones for zonal resources. Use [] in a region without zones."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "workload" {
  description = "Short workload name used in resource names (lower-case letters/digits)."
  type        = string
  default     = "hubspoke"

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.workload))
    error_message = "workload must be 2-10 lower-case letters or digits (it is part of the storage account name)."
  }
}

variable "environment" {
  description = "Environment short name."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9]{2,4}$", var.environment))
    error_message = "environment must be 2-4 lower-case letters or digits."
  }
}

variable "owner" {
  description = "Owner tag value (team or person accountable for cost)."
  type        = string
}

variable "repository" {
  description = "Repository tag value, so every resource points back to its source."
  type        = string
  default     = "azure-hub-spoke"
}

variable "extra_tags" {
  description = "Additional tags (e.g. cost-center). Mandatory tags take precedence."
  type        = map(string)
  default     = {}
}

# --- Network security --------------------------------------------------------

variable "enable_firewall" {
  description = "Deploy Azure Firewall in the hub and route spoke egress / spoke-to-spoke traffic through it. Dominant cost driver; see README."
  type        = bool
  default     = false
}

variable "firewall_sku_tier" {
  description = "Azure Firewall tier when enabled: Basic, Standard or Premium."
  type        = string
  default     = "Standard"
}

variable "waf_mode" {
  description = "Application Gateway WAF mode."
  type        = string
  default     = "Prevention"
}

variable "waf_admin_allowed_cidrs" {
  description = "Source ranges allowed to reach admin paths through the WAF. Empty = blocked for everyone."
  type        = list(string)
  default     = []
}

variable "waf_rate_limit_threshold" {
  description = "Requests per client IP per minute before the WAF rate-limit rule blocks."
  type        = number
  default     = 100
}

variable "app_gateway_dns_label" {
  description = "Optional DNS label for the gateway public IP."
  type        = string
  default     = null
}

# --- Workload ----------------------------------------------------------------

variable "deploy_backend_vm" {
  description = "Deploy the small backend VM (WAF backend and in-VNet verification vantage point)."
  type        = bool
  default     = true
}

variable "vm_size" {
  description = "Backend VM size."
  type        = string
  default     = "Standard_B2ats_v2"
}

variable "vm_admin_username" {
  description = "Local admin user on the backend VM (SSH key only; no inbound SSH rule exists)."
  type        = string
  default     = "azureops"
}

variable "vm_admin_ssh_public_key" {
  description = "OpenSSH public key for the backend VM admin user."
  type        = string
  default     = null

  validation {
    condition     = var.vm_admin_ssh_public_key == null || can(regex("^(ssh-rsa|ssh-ed25519) ", var.vm_admin_ssh_public_key))
    error_message = "vm_admin_ssh_public_key must be an OpenSSH ssh-rsa or ssh-ed25519 public key."
  }
}

variable "vm_encryption_at_host" {
  description = "Enable encryption at host (requires the Microsoft.Compute/EncryptionAtHost feature on the subscription)."
  type        = bool
  default     = false
}

# --- Data --------------------------------------------------------------------

variable "storage_replication_type" {
  description = "Storage replication. LRS for dev; ZRS/GZRS for production."
  type        = string
  default     = "LRS"
}

# --- Operations & cost -------------------------------------------------------

variable "log_daily_quota_gb" {
  description = "Log Analytics daily ingestion cap in GB (-1 = unlimited)."
  type        = number
  default     = 1
}

variable "monthly_budgets" {
  description = "Monthly budget (billing currency) per resource group."
  type = object({
    hub      = number
    workload = number
    data     = number
  })
  default = {
    hub      = 50
    workload = 100
    data     = 20
  }
}

variable "budget_contact_emails" {
  description = "Recipients of budget alerts."
  type        = list(string)

  validation {
    condition     = length(var.budget_contact_emails) > 0
    error_message = "At least one budget contact email is required."
  }
}
