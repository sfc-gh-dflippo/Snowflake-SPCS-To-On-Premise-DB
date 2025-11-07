# Azure Terraform Configuration

This directory contains Terraform configuration for deploying Snowflake Private Link connectivity infrastructure on Azure.

## Overview

This Terraform configuration creates:
- Virtual Network and subnets
- Internal Load Balancer
- Private Link Service
- Azure Private DNS Resolver with outbound endpoint
- DNS forwarding ruleset for on-premise domain
- Network Security Group
- All necessary connectivity for Snowflake Private Link

## Prerequisites

- Terraform >= 1.0
- Azure CLI configured with appropriate credentials
- Azure subscription with necessary permissions to create:
  - Virtual Networks
  - Load Balancers
  - Private Link Services
  - DNS Private Resolvers
  - Network Security Groups
- On-premise DNS server IP addresses for forwarding
- On-premise domain name to forward (e.g., corp.local)
- Available /28 subnet for DNS resolver outbound endpoint

## Quick Start

1. **Copy the example variables file:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit `terraform.tfvars` with your values:**
   - Update `on_premise_database_ip` with your database IP
   - Update `on_premise_database_port` with your database port
   - Update `on_premise_domain_name` with your internal domain
   - Update `on_premise_dns_server_ip1` and `on_premise_dns_server_ip2`
   - Update `snowflake_subscription_id` with Snowflake's Azure subscription ID
   - Adjust network addresses if needed (including DNS resolver subnet)

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
   After successful apply, copy the `private_link_service_alias` and `private_link_service_id` from the outputs and provide them to your Snowflake administrator.

## File Structure

```
azure-terraform/
├── main.tf                      # Main resource definitions
├── variables.tf                 # Variable declarations
├── outputs.tf                   # Output definitions
├── provider.tf                  # Provider and Terraform configuration
├── terraform.tfvars.example     # Example variable values
└── README.md                    # This file
```

## Important Outputs

After running `terraform apply`, note these critical outputs:

- **`private_link_service_alias`**: Provide this to your Snowflake administrator
- **`private_link_service_id`**: Provide this to your Snowflake administrator
- **`load_balancer_ip`**: Private IP of the load balancer
- **`dns_resolver_outbound_endpoint_ip`**: IP of DNS resolver for troubleshooting

## Configuration Details

### Virtual Network

The VNet is configured with:
- Customizable address space (default: 10.0.0.0/16)
- Subnet for load balancer and Private Link Service
- Network security groups for traffic control

### Load Balancer

The internal load balancer:
- Standard SKU for Private Link Service support
- TCP probe for health checking
- Load balancing rules for database port
- Backend pool for target endpoints

### Private Link Service

The Private Link Service:
- Connects to the load balancer frontend
- Allows Snowflake subscription to create private endpoint
- Requires manual approval of connections
- Provides secure, private connectivity

### DNS Private Resolver

The DNS resolver enables Snowflake to resolve on-premise DNS names:
- Outbound endpoint in dedicated, delegated subnet
- DNS forwarding ruleset for on-premise domain
- VNet link to enable DNS resolution
- Targets on-premise DNS servers for domain queries

## Security Considerations

1. **Network Security Groups**: Configure appropriate inbound/outbound rules
2. **Private Link Access**: Limit to Snowflake's subscription ID only
3. **Network Isolation**: Resources deployed in dedicated subnet
4. **Encryption**: All traffic over Private Link is encrypted

## Customization

### Remote State Backend

To use remote state storage, uncomment and configure the backend block in `provider.tf`:

```hcl
backend "azurerm" {
  resource_group_name  = "terraform-state-rg"
  storage_account_name = "tfstatestorage"
  container_name       = "tfstate"
  key                  = "snowflake-privatelink.tfstate"
}
```

### Additional Tags

Modify the `tags` variable in `terraform.tfvars` to add organization-specific tags.

## Troubleshooting

### Connection Not Working

1. Verify load balancer backend health is good
2. Check NSG rules allow traffic on database port
3. Confirm Private Link connection is approved
4. Validate on-premise database is accessible

### Private Link Service Issues

1. Check service state is "Ready"
2. Verify load balancer frontend is associated
3. Confirm Snowflake subscription ID is correct
4. Review Private Link service visibility settings

### DNS Resolution Issues

1. Verify DNS resolver is provisioned successfully
2. Check forwarding ruleset is linked to VNet
3. Confirm on-premise DNS servers are reachable
4. Test DNS resolution from Azure VMs in the VNet
5. Verify domain name ends with dot in forwarding rule

## Cleanup

To destroy all resources created by this configuration:

```bash
terraform destroy
```

**Warning**: This will delete all resources. Ensure you have backups and understand the implications.

## Support

For issues or questions:
1. Review the main documentation in `docs/04_azure_implementation.md`
2. Check Azure documentation for specific services
3. Verify Terraform provider version compatibility

## References

- [Azure Private Link Documentation](https://docs.microsoft.com/en-us/azure/private-link/)
- [Terraform AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Snowflake External Access Integration](https://docs.snowflake.com/en/sql-reference/sql/create-external-access-integration)

