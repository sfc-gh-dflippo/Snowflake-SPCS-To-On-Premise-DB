# Output values for Snowflake PrivateLink configuration

output "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer"
  value       = aws_lb.snowflake_onprem_nlb.dns_name
}

output "vpc_endpoint_service_id" {
  description = "The VPC Endpoint Service ID"
  value       = aws_vpc_endpoint_service.snowflake_vpc_endpoint_service.id
}

output "vpc_endpoint_service_name" {
  description = "CRITICAL: The VPC Endpoint Service Name - provide this to your Snowflake Administrator"
  value       = aws_vpc_endpoint_service.snowflake_vpc_endpoint_service.service_name
}

output "route53_resolver_endpoint_id" {
  description = "The Route 53 Resolver Outbound Endpoint ID"
  value       = aws_route53_resolver_endpoint.onprem_resolver_endpoint.id
}

output "route53_forwarding_rule_id" {
  description = "The Route 53 DNS Forwarding Rule ID"
  value       = aws_route53_resolver_rule.onprem_dns_forwarding_rule.id
}

output "target_group_arn" {
  description = "ARN of the NLB Target Group"
  value       = aws_lb_target_group.snowflake_onprem_target_group.arn
}

