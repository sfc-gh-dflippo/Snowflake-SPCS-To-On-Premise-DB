# AWS Terraform Configuration

This directory contains Terraform configuration for deploying Snowflake PrivateLink connectivity infrastructure on AWS.

## Overview

This Terraform configuration creates:
- Network Load Balancer (NLB) with target group
- VPC Endpoint Service for PrivateLink
- Route 53 Resolver Outbound Endpoint
- DNS forwarding rules for on-premise resolution
- Security groups and IAM roles

## Prerequisites

- Terraform >= 1.0
- AWS CLI configured with appropriate credentials
- AWS account with necessary permissions to create:
  - EC2 resources (Network Load Balancer, Target Groups, Security Groups)
  - VPC Endpoint Service
  - Route 53 Resolver resources (Outbound Endpoint, Forwarding Rules)
  - VPC resources (Routes, Network ACLs)
- Existing VPC with private subnets in at least 2 Availability Zones
- Transit Gateway connecting VPC to on-premise network
- On-premise DNS servers accessible from VPC

## Quick Start

1. **Copy the example variables file:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit `terraform.tfvars` with your values:**
   - Update `vpc_id` with your VPC ID
   - Update `subnet_id_1` and `subnet_id_2` with your private subnet IDs (must be in different AZs)
   - Update `route_table_id_1` and `route_table_id_2` with your route table IDs
   - Update `on_prem_database_ip` with your on-premise database IP address
   - Update `on_prem_cidr` with your on-premise network CIDR block
   - Update `on_prem_dns_server_ip_1` and `on_prem_dns_server_ip_2` with your DNS server IPs
   - Update `transit_gateway_id` with your Transit Gateway ID
   - Update `snowflake_vpc_cidr` with the CIDR block provided by Snowflake Support
   - Optionally modify `database_port` and `on_prem_domain_name` if your values differ from defaults

3. **Initialize Terraform:**
   ```bash
   terraform init
   ```

4. **Review the execution plan:**
   ```bash
   terraform plan
   ```

5. **Apply the configuration:**
   ```bash
   terraform apply
   ```

6. **Note the outputs:**
   After successful apply, copy the `vpc_endpoint_service_name` from the outputs and provide it to your Snowflake administrator.

## Deployment Time

**Expected Duration:** 5-10 minutes

Component breakdown:
- Network Load Balancer: ~2-3 minutes
- VPC Endpoint Service: ~1 minute
- Route 53 Resolver Endpoints: ~2-3 minutes
- Network ACL and Route creation: <1 minute

Note: Cost information intentionally omitted as pricing changes frequently. Consult AWS Pricing Calculator for current estimates.

## File Structure

```
aws-terraform/
├── main.tf                      # Main resource definitions
├── variables.tf                 # Variable declarations
├── outputs.tf                   # Output definitions
├── provider.tf                  # Provider and Terraform configuration
├── terraform.tfvars.example     # Example variable values
└── README.md                    # This file
```

## Important Outputs

After running `terraform apply`, note these critical outputs:

- **`vpc_endpoint_service_name`**: **CRITICAL** - Provide this to your Snowflake administrator to create the PrivateLink connection
- **`vpc_endpoint_service_id`**: The VPC Endpoint Service ID for reference
- **`nlb_dns_name`**: DNS name for the Network Load Balancer (used in Snowflake Network Rules)
- **`target_group_arn`**: ARN of the NLB Target Group (for monitoring and troubleshooting)
- **`route53_resolver_endpoint_id`**: Route 53 Resolver Outbound Endpoint ID
- **`route53_forwarding_rule_id`**: DNS Forwarding Rule ID for on-premise domain resolution

To view all outputs:
```bash
terraform output
```

## Configuration Details

### Network Load Balancer

The NLB is configured with:
- Internal load balancer (not internet-facing)
- TCP listener on the database port
- Health checks configured for target group
- Cross-zone load balancing enabled

### VPC Endpoint Service

The VPC Endpoint Service:
- Allows Snowflake's AWS account to create a PrivateLink connection
- Requires manual acceptance of connection requests
- Supports DNS resolution for private connectivity

### Route 53 Resolver

The outbound resolver endpoint:
- Forwards DNS queries for on-premise domains
- Requires specification of on-premise DNS server IPs
- Enables SPCS services to resolve on-premise hostnames

## Security Considerations

1. **Security Groups**: The DNS resolver security group only allows egress to on-premise DNS servers on port 53 (UDP and TCP)
2. **VPC Endpoint Service**: Configure acceptance_required=true (default in this config) to manually approve Snowflake connection requests
3. **Network ACLs**: Configured to allow traffic only between Snowflake VPC CIDR, on-premise CIDR, and ephemeral ports
4. **Network Isolation**: Deploy in private subnets (no internet gateway route required)
5. **Transit Gateway**: Ensure Transit Gateway route tables are properly configured for on-premise connectivity

**Post-Deployment Security Steps:**
1. Add Snowflake principal ARN to VPC Endpoint Service allowed principals
2. Manually accept connection request from Snowflake after they provision their endpoint
3. Verify target group health checks are passing before enabling production traffic

## Customization

### Remote State Backend

To use remote state storage, uncomment and configure the backend block in `provider.tf`:

```hcl
backend "s3" {
  bucket         = "your-terraform-state-bucket"
  key            = "snowflake-privatelink/terraform.tfstate"
  region         = "us-west-2"
  encrypt        = true
  dynamodb_table = "terraform-state-lock"
}
```

### Additional Tags

Modify the `default_tags` block in `provider.tf` to add organization-specific tags.

## Troubleshooting

### Terraform Errors

**Issue: "Error creating VPC Endpoint Service"**
- Verify NLB exists and is in `active` state
- Ensure NLB is of type `network` (not `application`)
- Check IAM permissions for VPC endpoint service creation

**Issue: "Error creating Route 53 Resolver Endpoint"**
- Verify subnets have available IP addresses (minimum 1 per subnet)
- Ensure subnets are in different Availability Zones
- Check security group allows outbound DNS traffic to on-premise DNS servers

For additional troubleshooting, see Chapter 6, Section 6.1.4, 6.1.5, and 6.2.5.

### Connection Not Working

1. Verify target group health checks are passing
2. Check security group rules allow traffic on database port
3. Confirm VPC Endpoint Service connection is accepted
4. Validate Route 53 resolver rules are active

### DNS Resolution Failures

1. Check Route 53 Resolver endpoint status (must be "OPERATIONAL")
2. Verify forwarding rules are associated with VPC
3. Confirm on-premise DNS servers are accessible
4. Test DNS resolution from within the VPC

## Cleanup

To destroy all resources created by this configuration:

```bash
# Review what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy
```

**Warning**: This will permanently delete all resources including:
- Network Load Balancer and Target Groups
- VPC Endpoint Service (breaks active Snowflake connections)
- Route 53 Resolver endpoints and rules
- Network ACL rules and routes

Ensure you have:
- Notified Snowflake administrators
- Backed up any configuration information
- Verified no active connections are using these resources

## Support

For issues or questions:
1. Review the main documentation in `docs/03_aws_implementation.md`
2. Check AWS documentation for specific services
3. Verify Terraform provider version compatibility

## References

- [AWS PrivateLink Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Snowflake External Access Integration](https://docs.snowflake.com/en/sql-reference/sql/create-external-access-integration)

