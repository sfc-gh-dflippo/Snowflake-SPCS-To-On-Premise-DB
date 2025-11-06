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
  description = "Port number of the on-premise database"
  type        = number
  default     = 3306
}

variable "snowflake_subscription_id" {
  description = "Snowflake's Azure subscription ID for Private Link connection"
  type        = string
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

