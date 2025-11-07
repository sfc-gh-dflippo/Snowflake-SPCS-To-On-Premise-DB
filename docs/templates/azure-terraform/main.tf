# Azure Infrastructure for Snowflake Private Link

# Resource Group
resource "azurerm_resource_group" "snowflake_privatelink_rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Virtual Network
resource "azurerm_virtual_network" "snowflake_privatelink_vnet" {
  name                = var.vnet_name
  location            = azurerm_resource_group.snowflake_privatelink_rg.location
  resource_group_name = azurerm_resource_group.snowflake_privatelink_rg.name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

# Subnet for Load Balancer and Private Link Service
resource "azurerm_subnet" "snowflake_privatelink_subnet" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.snowflake_privatelink_rg.name
  virtual_network_name = azurerm_virtual_network.snowflake_privatelink_vnet.name
  address_prefixes     = [var.subnet_address_prefix]

  # Disable private link service network policies
  private_link_service_network_policies_enabled = false
}

# DNS Resolver Outbound Endpoint Subnet
resource "azurerm_subnet" "dns_resolver_outbound" {
  name                 = "snet-dns-outbound"
  resource_group_name  = azurerm_resource_group.snowflake_privatelink_rg.name
  virtual_network_name = azurerm_virtual_network.snowflake_privatelink_vnet.name
  address_prefixes     = [var.dns_resolver_outbound_subnet_prefix]

  delegation {
    name = "Microsoft.Network.dnsResolvers"
    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Standard Load Balancer
resource "azurerm_lb" "snowflake_privatelink_lb" {
  name                = var.load_balancer_name
  location            = azurerm_resource_group.snowflake_privatelink_rg.location
  resource_group_name = azurerm_resource_group.snowflake_privatelink_rg.name
  sku                 = "Standard"
  tags                = var.tags

  frontend_ip_configuration {
    name                          = "LoadBalancerFrontEnd"
    subnet_id                     = azurerm_subnet.snowflake_privatelink_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Backend Address Pool
resource "azurerm_lb_backend_address_pool" "snowflake_backend_pool" {
  name            = "snowflake-backend-pool"
  loadbalancer_id = azurerm_lb.snowflake_privatelink_lb.id
}

# Backend Address Pool Address (points to on-premise database)
resource "azurerm_lb_backend_address_pool_address" "onprem_db" {
  name                    = "onprem-database"
  backend_address_pool_id = azurerm_lb_backend_address_pool.snowflake_backend_pool.id
  virtual_network_id      = azurerm_virtual_network.snowflake_privatelink_vnet.id
  ip_address              = var.on_premise_database_ip
}

# Health Probe
resource "azurerm_lb_probe" "snowflake_probe" {
  name            = "database-health-probe"
  loadbalancer_id = azurerm_lb.snowflake_privatelink_lb.id
  port            = var.on_premise_database_port
  protocol        = "Tcp"
}

# Load Balancing Rule
resource "azurerm_lb_rule" "snowflake_lb_rule" {
  name                           = "database-lb-rule"
  loadbalancer_id                = azurerm_lb.snowflake_privatelink_lb.id
  frontend_ip_configuration_name = "LoadBalancerFrontEnd"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.snowflake_backend_pool.id]
  probe_id                       = azurerm_lb_probe.snowflake_probe.id
  protocol                       = "Tcp"
  frontend_port                  = var.on_premise_database_port
  backend_port                   = var.on_premise_database_port
  enable_floating_ip             = false
  idle_timeout_in_minutes        = 4
}

# Private Link Service
resource "azurerm_private_link_service" "snowflake_privatelink_service" {
  name                = var.private_link_service_name
  location            = azurerm_resource_group.snowflake_privatelink_rg.location
  resource_group_name = azurerm_resource_group.snowflake_privatelink_rg.name
  tags                = var.tags

  load_balancer_frontend_ip_configuration_ids = [
    azurerm_lb.snowflake_privatelink_lb.frontend_ip_configuration[0].id
  ]

  nat_ip_configuration {
    name                       = "primary"
    subnet_id                  = azurerm_subnet.snowflake_privatelink_subnet.id
    primary                    = true
    private_ip_address_version = "IPv4"
  }

  # Snowflake subscription visibility
  visibility_subscription_ids = [var.snowflake_subscription_id]

  # Auto-approval for Snowflake subscription
  auto_approval_subscription_ids = [var.snowflake_subscription_id]
}

# DNS Private Resolver
resource "azurerm_private_dns_resolver" "hub_resolver" {
  name                = "dns-resolver-hub"
  resource_group_name = azurerm_resource_group.snowflake_privatelink_rg.name
  location            = azurerm_resource_group.snowflake_privatelink_rg.location
  virtual_network_id  = azurerm_virtual_network.snowflake_privatelink_vnet.id
  tags                = var.tags
}

# DNS Resolver Outbound Endpoint
resource "azurerm_private_dns_resolver_outbound_endpoint" "onprem" {
  name                    = "onprem-dns-outbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub_resolver.id
  location                = azurerm_resource_group.snowflake_privatelink_rg.location
  subnet_id               = azurerm_subnet.dns_resolver_outbound.id
  tags                    = var.tags
}

# DNS Forwarding Ruleset
resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "onprem" {
  name                                       = "onprem-dns-ruleset"
  resource_group_name                        = azurerm_resource_group.snowflake_privatelink_rg.name
  location                                   = azurerm_resource_group.snowflake_privatelink_rg.location
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.onprem.id]
  tags                                       = var.tags
}

# DNS Forwarding Rule for On-Premise Domain
resource "azurerm_private_dns_resolver_forwarding_rule" "onprem_domain" {
  name                      = "onprem-forwarding-rule"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.onprem.id
  domain_name               = "${var.on_premise_domain_name}."
  enabled                   = true

  target_dns_servers {
    ip_address = var.on_premise_dns_server_ip1
    port       = 53
  }

  target_dns_servers {
    ip_address = var.on_premise_dns_server_ip2
    port       = 53
  }
}

# VNet Link for DNS Forwarding Ruleset
resource "azurerm_private_dns_resolver_virtual_network_link" "hub_link" {
  name                      = "hub-vnet-link"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.onprem.id
  virtual_network_id        = azurerm_virtual_network.snowflake_privatelink_vnet.id
}

# Network Security Group
resource "azurerm_network_security_group" "snowflake_nsg" {
  name                = "${var.subnet_name}-nsg"
  location            = azurerm_resource_group.snowflake_privatelink_rg.location
  resource_group_name = azurerm_resource_group.snowflake_privatelink_rg.name
  tags                = var.tags

  # Allow Azure Load Balancer health probes
  security_rule {
    name                       = "AllowAzureLoadBalancerProbe"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "AzureLoadBalancer"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = tostring(var.on_premise_database_port)
  }

  # Allow traffic from Private Link Service
  security_rule {
    name                       = "AllowPrivateLinkService"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "VirtualNetwork"
    source_port_range          = "*"
    destination_address_prefix = var.subnet_address_prefix
    destination_port_range     = tostring(var.on_premise_database_port)
  }

  # Allow outbound to on-premise database
  security_rule {
    name                       = "AllowToOnPremise"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "VirtualNetwork"
    source_port_range          = "*"
    destination_address_prefix = var.on_premise_database_ip
    destination_port_range     = tostring(var.on_premise_database_port)
  }

  # Allow all other outbound
  security_rule {
    name                       = "AllowOtherOutbound"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }
}

# Associate NSG with Subnet
resource "azurerm_subnet_network_security_group_association" "snowflake_nsg_association" {
  subnet_id                 = azurerm_subnet.snowflake_privatelink_subnet.id
  network_security_group_id = azurerm_network_security_group.snowflake_nsg.id
}
