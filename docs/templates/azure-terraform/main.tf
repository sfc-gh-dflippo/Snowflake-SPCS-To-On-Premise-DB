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

# Network Security Group
resource "azurerm_network_security_group" "snowflake_nsg" {
  name                = "${var.subnet_name}-nsg"
  location            = azurerm_resource_group.snowflake_privatelink_rg.location
  resource_group_name = azurerm_resource_group.snowflake_privatelink_rg.name
  tags                = var.tags

  security_rule {
    name                       = "AllowSnowflakeInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = var.subnet_address_prefix
    destination_port_range     = tostring(var.on_premise_database_port)
  }

  security_rule {
    name                       = "AllowOutbound"
    priority                   = 100
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
