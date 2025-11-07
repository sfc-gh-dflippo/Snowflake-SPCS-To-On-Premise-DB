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
  value       = azurerm_lb.snowflake_privatelink_lb.frontend_ip_configuration[0].private_ip_address
}

output "private_link_service_id" {
  description = "CRITICAL: The Private Link Service ID - provide this to your Snowflake Administrator"
  value       = azurerm_private_link_service.snowflake_privatelink_service.id
}

output "private_link_service_alias" {
  description = "CRITICAL: The Private Link Service Alias - provide this to your Snowflake Administrator"
  value       = azurerm_private_link_service.snowflake_privatelink_service.alias
}

output "dns_resolver_id" {
  description = "ID of the DNS Private Resolver"
  value       = azurerm_private_dns_resolver.hub_resolver.id
}

output "dns_resolver_outbound_endpoint_id" {
  description = "ID of the DNS resolver outbound endpoint"
  value       = azurerm_private_dns_resolver_outbound_endpoint.onprem.id
}

output "dns_forwarding_ruleset_id" {
  description = "ID of the DNS forwarding ruleset"
  value       = azurerm_private_dns_resolver_dns_forwarding_ruleset.onprem.id
}

