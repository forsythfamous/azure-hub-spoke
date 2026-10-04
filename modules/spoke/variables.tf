variable "name" {
  description = "Spoke VNet name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the spoke."
  type        = string
}

variable "address_space" {
  description = "Spoke VNet CIDR. Must not overlap the hub or other spokes."
  type        = string
}

variable "subnets" {
  description = <<-EOT
    Subnets keyed by name. Each gets its own NSG built from nsg_rules.
    Add an explicit Deny-All-Inbound at priority 4096 so the effective policy
    does not depend on Azure's permissive AllowVnetInBound default.
  EOT
  type = map(object({
    address_prefix                    = string
    route_via_firewall                = optional(bool, false)
    default_outbound_access_enabled   = optional(bool, false)
    private_endpoint_network_policies = optional(string, "Disabled")
    nsg_rules = list(object({
      name                 = string
      priority             = number
      direction            = string
      access               = string
      protocol             = string
      source_prefixes      = list(string)
      destination_prefixes = optional(list(string), ["*"])
      destination_ports    = optional(list(string), ["*"])
    }))
  }))
}

variable "hub_vnet_id" {
  description = "Hub VNet ID to peer with."
  type        = string
}

variable "hub_vnet_name" {
  description = "Hub VNet name (for the hub-side peering)."
  type        = string
}

variable "hub_resource_group_name" {
  description = "Hub resource group (for the hub-side peering)."
  type        = string
}

variable "enable_firewall_routing" {
  description = "Attach a 0.0.0.0/0 -> firewall route table to subnets with route_via_firewall = true."
  type        = bool
  default     = false
}

variable "firewall_private_ip" {
  description = "Next hop for the default route. Required when enable_firewall_routing is true."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_firewall_routing || var.firewall_private_ip != null
    error_message = "firewall_private_ip must be set when enable_firewall_routing is true."
  }
}

variable "private_dns_zone_names" {
  description = "Private DNS zones (hosted in the hub) to link this VNet to."
  type        = list(string)
  default     = []
}

variable "private_dns_zone_resource_group_name" {
  description = "Resource group that holds the Private DNS zones."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
