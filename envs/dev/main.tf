# Composition for the dev environment: hub, two spokes, data and workload
# tiers, monitoring and budgets. Modules hold mechanics; the policy
# (address plan, NSG rules, firewall rules) is visible here.

resource "azurerm_resource_group" "hub" {
  name     = local.names.rg_hub
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "workload" {
  name     = local.names.rg_workload
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "data" {
  name     = local.names.rg_data
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Hub
# ---------------------------------------------------------------------------

module "hub" {
  source = "../../modules/hub"

  name                              = local.names.vnet_hub
  location                          = var.location
  resource_group_name               = azurerm_resource_group.hub.name
  address_space                     = local.address.hub
  firewall_subnet_prefix            = local.address.hub_firewall
  firewall_management_subnet_prefix = local.address.hub_firewall_mgmt
  shared_subnet_prefix              = local.address.hub_shared
  trusted_address_prefixes          = [local.address.workload, local.address.data]
  private_dns_zones                 = local.private_dns_zones
  zones                             = var.zones

  enable_firewall   = var.enable_firewall
  firewall_name     = local.names.firewall
  firewall_sku_tier = var.firewall_sku_tier

  # Spoke-to-spoke transit is denied unless listed here. The only flow the
  # design needs: the app tier reading blobs through the private endpoint.
  firewall_application_rules = {
    workload-app-to-storage-blob = {
      source_addresses  = [local.address.workload_app]
      destination_fqdns = ["${local.names.storage}.blob.core.windows.net"]
    }
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Workload spoke: Application Gateway WAF_v2 + app tier
# ---------------------------------------------------------------------------

module "spoke_workload" {
  source = "../../modules/spoke"

  name                = local.names.vnet_workload
  location            = var.location
  resource_group_name = azurerm_resource_group.workload.name
  address_space       = local.address.workload

  hub_vnet_id             = module.hub.vnet_id
  hub_vnet_name           = module.hub.vnet_name
  hub_resource_group_name = azurerm_resource_group.hub.name

  enable_firewall_routing = var.enable_firewall
  firewall_private_ip     = module.hub.firewall_private_ip

  private_dns_zone_names               = local.private_dns_zones
  private_dns_zone_resource_group_name = azurerm_resource_group.hub.name

  subnets = {
    # Application Gateway v2: no UDR towards an NVA (unsupported for 0/0),
    # and the GatewayManager / AzureLoadBalancer rules are mandatory.
    snet-appgw = {
      address_prefix                  = local.address.workload_appgw
      default_outbound_access_enabled = true
      nsg_rules = [
        {
          name              = "Allow-Internet-HTTP-HTTPS-Inbound"
          priority          = 100
          direction         = "Inbound"
          access            = "Allow"
          protocol          = "Tcp"
          source_prefixes   = ["Internet"]
          destination_ports = ["80", "443"]
        },
        {
          name              = "Allow-GatewayManager-Inbound"
          priority          = 110
          direction         = "Inbound"
          access            = "Allow"
          protocol          = "Tcp"
          source_prefixes   = ["GatewayManager"]
          destination_ports = ["65200-65535"]
        },
        {
          name            = "Allow-AzureLoadBalancer-Inbound"
          priority        = 120
          direction       = "Inbound"
          access          = "Allow"
          protocol        = "*"
          source_prefixes = ["AzureLoadBalancer"]
        },
        local.deny_all_inbound,
      ]
    }

    # App tier: reachable only from the gateway subnet. Egress (when the
    # firewall is enabled) is forced through the hub.
    snet-app = {
      address_prefix     = local.address.workload_app
      route_via_firewall = true
      nsg_rules = [
        {
          name                 = "Allow-AppGw-HTTP-Inbound"
          priority             = 100
          direction            = "Inbound"
          access               = "Allow"
          protocol             = "Tcp"
          source_prefixes      = [local.address.workload_appgw]
          destination_prefixes = [local.address.workload_app]
          destination_ports    = ["80"]
        },
        {
          name            = "Allow-AzureLoadBalancer-Inbound"
          priority        = 110
          direction       = "Inbound"
          access          = "Allow"
          protocol        = "*"
          source_prefixes = ["AzureLoadBalancer"]
        },
        local.deny_all_inbound,
      ]
    }
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Data spoke: private endpoints only
# ---------------------------------------------------------------------------

module "spoke_data" {
  source = "../../modules/spoke"

  name                = local.names.vnet_data
  location            = var.location
  resource_group_name = azurerm_resource_group.data.name
  address_space       = local.address.data

  hub_vnet_id             = module.hub.vnet_id
  hub_vnet_name           = module.hub.vnet_name
  hub_resource_group_name = azurerm_resource_group.hub.name

  enable_firewall_routing = var.enable_firewall
  firewall_private_ip     = module.hub.firewall_private_ip

  private_dns_zone_names               = local.private_dns_zones
  private_dns_zone_resource_group_name = azurerm_resource_group.hub.name

  subnets = {
    snet-private-endpoints = {
      address_prefix = local.address.data_private_links
      # Make the NSG apply to private endpoint traffic (off by default).
      private_endpoint_network_policies = "NetworkSecurityGroupEnabled"
      nsg_rules = [
        {
          # Firewall application rules SNAT, so workload traffic arrives
          # from the AzureFirewallSubnet range.
          name      = "Allow-HTTPS-From-App-And-Firewall"
          priority  = 100
          direction = "Inbound"
          access    = "Allow"
          protocol  = "Tcp"
          source_prefixes = [
            local.address.workload_app,
            local.address.hub_firewall,
            local.address.hub_shared,
          ]
          destination_prefixes = [local.address.data_private_links]
          destination_ports    = ["443"]
        },
        local.deny_all_inbound,
      ]
    }
  }

  tags = local.tags
}
