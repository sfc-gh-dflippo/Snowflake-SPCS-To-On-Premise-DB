# Output values for Snowflake Private Link configuration

output "resource_group_name" {
  description = "Name of the Resource Group"
  value       = azurerm_resource_group.snowflake_privatelink_rg.name
}

output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = azurerm_virtual_network.snowflake_privatelink_vnet.id
}

output "load_balancer_ip" {
  description = "Private IP address of the Load Balancer"
  value       = azurerm_lb.snowflake_privatelink_lb.private_ip_address
}

output "private_link_service_id" {
  description = "CRITICAL: The Private Link Service ID - provide this to your Snowflake Administrator"
  value       = azurerm_private_link_service.snowflake_privatelink_service.id
}

output "private_link_service_alias" {
  description = "CRITICAL: The Private Link Service Alias - provide this to your Snowflake Administrator"
  value       = azurerm_private_link_service.snowflake_privatelink_service.alias
}

