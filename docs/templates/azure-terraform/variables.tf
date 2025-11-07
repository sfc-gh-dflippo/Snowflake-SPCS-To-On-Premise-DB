# Azure Terraform Variables

variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "West US 2"
}

variable "vnet_name" {
  description = "Name of the Virtual Network"
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the Virtual Network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
}

variable "subnet_address_prefix" {
  description = "Address prefix for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "load_balancer_name" {
  description = "Name of the Azure Load Balancer"
  type        = string
}

variable "private_link_service_name" {
  description = "Name of the Private Link Service"
  type        = string
}

variable "on_premise_database_ip" {
  description = "IP address of the on-premise database"
  type        = string
}

variable "on_premise_database_port" {
  description = "Port number of the on-premise database (default: 1433 for SQL Server)"
  type        = number
  default     = 1433

  validation {
    condition     = var.on_premise_database_port > 0 && var.on_premise_database_port <= 65535
    error_message = "Port must be between 1 and 65535."
  }
}

variable "on_premise_domain_name" {
  description = "The on-premise domain name for DNS forwarding (e.g., corp.local)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$", var.on_premise_domain_name))
    error_message = "Must be a valid domain name."
  }
}

variable "on_premise_dns_server_ip1" {
  description = "IP address of the first on-premise DNS server"
  type        = string

  validation {
    condition     = can(cidrhost("${var.on_premise_dns_server_ip1}/32", 0))
    error_message = "Must be a valid IPv4 address."
  }
}

variable "on_premise_dns_server_ip2" {
  description = "IP address of the second on-premise DNS server"
  type        = string

  validation {
    condition     = can(cidrhost("${var.on_premise_dns_server_ip2}/32", 0))
    error_message = "Must be a valid IPv4 address."
  }
}

variable "dns_resolver_outbound_subnet_prefix" {
  description = "Address prefix for DNS resolver outbound endpoint subnet (minimum /28)"
  type        = string
  default     = "10.0.10.0/28"

  validation {
    condition     = tonumber(split("/", var.dns_resolver_outbound_subnet_prefix)[1]) <= 28
    error_message = "DNS resolver subnet must be /28 or larger."
  }
}

variable "snowflake_subscription_id" {
  description = "Snowflake's Azure subscription ID for Private Link connection"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.snowflake_subscription_id))
    error_message = "Snowflake subscription ID must be a valid UUID."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "Snowflake-PrivateLink"
    ManagedBy   = "Terraform"
    Environment = "Production"
  }
}

