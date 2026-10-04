variable "name" {
  description = "Application Gateway name."
  type        = string
}

variable "waf_policy_name" {
  description = "WAF policy name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the gateway, its public IP and WAF policy."
  type        = string
}

variable "subnet_id" {
  description = "Dedicated Application Gateway subnet (/24 recommended for v2)."
  type        = string
}

variable "zones" {
  description = "Availability zones. Use [] in regions without zones."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "dns_label" {
  description = "Optional DNS label for the public IP (<label>.<region>.cloudapp.azure.com)."
  type        = string
  default     = null
}

variable "min_capacity" {
  description = "Autoscale minimum instance count. 0 = pay only the fixed gateway-hour when idle."
  type        = number
  default     = 0
}

variable "max_capacity" {
  description = "Autoscale maximum instance count (cost ceiling)."
  type        = number
  default     = 2
}

variable "backend_ip_addresses" {
  description = "Private IPs of backend targets."
  type        = list(string)
  default     = []
}

variable "backend_port" {
  description = "Backend HTTP port."
  type        = number
  default     = 80
}

variable "health_probe_path" {
  description = "Path probed on each backend."
  type        = string
  default     = "/"
}

variable "waf_mode" {
  description = "WAF mode. Prevention blocks; Detection only logs."
  type        = string
  default     = "Prevention"

  validation {
    condition     = contains(["Prevention", "Detection"], var.waf_mode)
    error_message = "waf_mode must be Prevention or Detection."
  }
}

variable "drs_version" {
  description = "Microsoft Default Rule Set version."
  type        = string
  default     = "2.1"
}

variable "admin_path_prefixes" {
  description = "URI prefixes (lower-case) treated as administrative."
  type        = list(string)
  default     = ["/admin", "/wp-admin", "/.env"]
}

variable "admin_allowed_cidrs" {
  description = "Source ranges allowed to reach admin_path_prefixes. Empty = blocked for everyone."
  type        = list(string)
  default     = []
}

variable "rate_limit_threshold" {
  description = "Requests per client IP per rate_limit_duration before blocking."
  type        = number
  default     = 100
}

variable "rate_limit_duration" {
  description = "Rate-limit window."
  type        = string
  default     = "OneMin"

  validation {
    condition     = contains(["OneMin", "FiveMins"], var.rate_limit_duration)
    error_message = "rate_limit_duration must be OneMin or FiveMins."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
