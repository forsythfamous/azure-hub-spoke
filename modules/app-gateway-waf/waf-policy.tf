# WAF policy: Microsoft Default Rule Set + Bot Manager in Prevention mode,
# evaluated after two custom rules (custom rules always run first, by
# ascending priority). See ADR-0004.

resource "azurerm_web_application_firewall_policy" "this" {
  name                = var.waf_policy_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  policy_settings {
    enabled                          = true
    mode                             = var.waf_mode
    request_body_check               = true
    request_body_enforcement         = true
    request_body_inspect_limit_in_kb = 128
    max_request_body_size_in_kb      = 128
    file_upload_limit_in_mb          = 100

    # Keep credentials and session tokens out of the WAF logs.
    log_scrubbing {
      enabled = true

      rule {
        match_variable          = "RequestHeaderNames"
        selector_match_operator = "Equals"
        selector                = "Authorization"
      }

      rule {
        match_variable          = "RequestCookieNames"
        selector_match_operator = "EqualsAny"
      }
    }
  }

  managed_rules {
    managed_rule_set {
      type    = "Microsoft_DefaultRuleSet"
      version = var.drs_version
    }

    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.1"
    }
  }

  # --- Custom rule 1: restrict an administrative path to known source ranges.
  # With no ranges configured the path is blocked for everyone.
  custom_rules {
    name      = "BlockAdminPathFromUntrusted"
    priority  = 10
    rule_type = "MatchRule"
    action    = "Block"

    match_conditions {
      match_variables {
        variable_name = "RequestUri"
      }
      operator           = "BeginsWith"
      match_values       = var.admin_path_prefixes
      transforms         = ["Lowercase", "UrlDecode"]
      negation_condition = false
    }

    dynamic "match_conditions" {
      for_each = length(var.admin_allowed_cidrs) > 0 ? [1] : []
      content {
        match_variables {
          variable_name = "RemoteAddr"
        }
        operator           = "IPMatch"
        match_values       = var.admin_allowed_cidrs
        negation_condition = true
      }
    }
  }

  # --- Custom rule 2: per-client rate limit. Matches every request (the
  # negated /32 never matches a real client) and counts per client IP.
  custom_rules {
    name                 = "RateLimitPerClientIp"
    priority             = 20
    rule_type            = "RateLimitRule"
    action               = "Block"
    rate_limit_duration  = var.rate_limit_duration
    rate_limit_threshold = var.rate_limit_threshold
    group_rate_limit_by  = "ClientAddr"

    match_conditions {
      match_variables {
        variable_name = "RemoteAddr"
      }
      operator           = "IPMatch"
      match_values       = ["255.255.255.255/32"]
      negation_condition = true
    }
  }
}
