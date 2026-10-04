# Application Gateway WAF_v2 with a single HTTP listener in front of a
# private backend pool. Autoscaling from 0 keeps idle cost at the fixed
# gateway-hour charge.

locals {
  frontend_ip_name      = "fip-public"
  frontend_port_name    = "port-http"
  backend_pool_name     = "pool-default"
  backend_settings_name = "bes-http"
  probe_name            = "probe-http"
  listener_name         = "lsn-http"
  rule_name             = "rule-http"
}

resource "azurerm_public_ip" "this" {
  name                = "pip-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones
  domain_name_label   = var.dns_label
  tags                = var.tags
}

resource "azurerm_application_gateway" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  zones               = var.zones
  http2_enabled       = true
  tags                = var.tags

  firewall_policy_id                = azurerm_web_application_firewall_policy.this.id
  force_firewall_policy_association = true

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  # Applies as soon as an HTTPS listener is added; TLS < 1.2 is never offered.
  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101S"
  }

  gateway_ip_configuration {
    name      = "gwipc"
    subnet_id = var.subnet_id
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_name
    public_ip_address_id = azurerm_public_ip.this.id
  }

  frontend_port {
    name = local.frontend_port_name
    port = 80
  }

  backend_address_pool {
    name         = local.backend_pool_name
    ip_addresses = var.backend_ip_addresses
  }

  probe {
    name                                      = local.probe_name
    protocol                                  = "Http"
    path                                      = var.health_probe_path
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
  }

  backend_http_settings {
    name                                = local.backend_settings_name
    protocol                            = "Http"
    port                                = var.backend_port
    cookie_based_affinity               = "Disabled"
    request_timeout                     = 30
    probe_name                          = local.probe_name
    pick_host_name_from_backend_address = true
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.rule_name
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_pool_name
    backend_http_settings_name = local.backend_settings_name
  }
}
