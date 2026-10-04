variable "name" {
  description = "Private endpoint name."
  type        = string
}

variable "location" {
  description = "Azure region (must match the subnet's VNet)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the private endpoint."
  type        = string
}

variable "subnet_id" {
  description = "Subnet that receives the endpoint's NIC."
  type        = string
}

variable "target_resource_id" {
  description = "Resource exposed through the endpoint (e.g. a storage account)."
  type        = string
}

variable "subresource_name" {
  description = "Target sub-resource / group ID, e.g. blob, file, vault."
  type        = string
}

variable "private_dns_zone_ids" {
  description = "Private DNS zone(s) in which Azure registers the endpoint's A record."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to the endpoint."
  type        = map(string)
  default     = {}
}
