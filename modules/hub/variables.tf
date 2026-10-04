variable "name" {
  description = "Hub VNet name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for all hub resources."
  type        = string
}

variable "address_space" {
  description = "Hub VNet CIDR."
  type        = string
}

variable "firewall_subnet_prefix" {
  description = "AzureFirewallSubnet CIDR (/26 minimum)."
  type        = string
}

variable "firewall_management_subnet_prefix" {
  description = "AzureFirewallManagementSubnet CIDR (/26 minimum; used by the Basic SKU)."
  type        = string
}

variable "shared_subnet_prefix" {
  description = "Shared services subnet CIDR."
  type        = string
}

variable "trusted_address_prefixes" {
  description = "Address ranges (normally the spoke address spaces) allowed into the shared services subnet."
  type        = list(string)
}

variable "private_dns_zones" {
  description = "privatelink.* zones hosted in the hub and linked to every VNet."
  type        = list(string)
}

variable "enable_firewall" {
  description = "Deploy Azure Firewall and its policy. Off by default: it dominates the monthly cost."
  type        = bool
  default     = false
}

variable "firewall_name" {
  description = "Azure Firewall name (also used to derive policy and public IP names)."
  type        = string
}

variable "firewall_sku_tier" {
  description = "Azure Firewall tier."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.firewall_sku_tier)
    error_message = "firewall_sku_tier must be Basic, Standard or Premium."
  }
}

variable "firewall_application_rules" {
  description = "Application (FQDN) rules, keyed by rule name. HTTPS/443 only."
  type = map(object({
    source_addresses  = list(string)
    destination_fqdns = list(string)
  }))
  default = {}
}

variable "firewall_network_rules" {
  description = "Network (L4) rules, keyed by rule name."
  type = map(object({
    protocols             = list(string)
    source_addresses      = list(string)
    destination_addresses = list(string)
    destination_ports     = list(string)
  }))
  default = {}
}

variable "zones" {
  description = "Availability zones for the firewall and its public IPs. Use [] in regions without zones."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
