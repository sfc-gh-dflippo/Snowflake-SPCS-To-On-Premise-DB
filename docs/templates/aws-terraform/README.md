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
  - EC2 resources (NLB, security groups)
  - VPC Endpoint Service
  - Route 53 Resolver resources
  - IAM roles and policies

## Quick Start

1. **Copy the example variables file:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit `terraform.tfvars` with your values:**
   - Update `vpc_id` with your VPC ID
   - Update `subnet_ids` with your subnet IDs
   - Update `on_premise_db_*` with your database details
   - Update `snowflake_account_id` with your Snowflake AWS account ID

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

- **`vpc_endpoint_service_name`**: Provide this to your Snowflake administrator to create the PrivateLink connection
- **`nlb_dns_name`**: DNS name for the Network Load Balancer
- **`route53_resolver_endpoint_id`**: Used for DNS forwarding configuration

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

1. **Security Groups**: Configure appropriate inbound/outbound rules
2. **IAM Permissions**: Use least privilege principle for service roles
3. **VPC Endpoint Access**: Limit to Snowflake's AWS account ID only
4. **Network Isolation**: Deploy in private subnets when possible

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

### Connection Not Working

1. Verify target group health checks are passing
2. Check security group rules allow traffic on database port
3. Confirm VPC Endpoint Service connection is accepted
4. Validate Route 53 resolver rules are active

### DNS Resolution Failures

1. Check Route 53 Resolver endpoint status
2. Verify forwarding rules are associated with VPC
3. Confirm on-premise DNS servers are accessible
4. Test DNS resolution from within the VPC

## Cleanup

To destroy all resources created by this configuration:

```bash
terraform destroy
```

**Warning**: This will delete all resources. Ensure you have backups and understand the implications.

## Support

For issues or questions:
1. Review the main documentation in `docs/03_aws_implementation.md`
2. Check AWS documentation for specific services
3. Verify Terraform provider version compatibility

## References

- [AWS PrivateLink Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Snowflake External Access Integration](https://docs.snowflake.com/en/sql-reference/sql/create-external-access-integration)

