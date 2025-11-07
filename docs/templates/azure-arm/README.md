# Azure ARM Template

This directory contains an Azure Resource Manager (ARM) template for deploying Snowflake Private Link connectivity infrastructure.

## Overview

This ARM template creates:
- Standard Load Balancer (internal)
- Private Link Service
- DNS Resolver and forwarding rules
- Network Security Group
- All necessary networking components

## Prerequisites

- Azure CLI configured with appropriate credentials
- Azure subscription with necessary permissions
- Existing Virtual Network
- Dedicated subnet for DNS resolver outbound endpoint (minimum /28)
  - Must be delegated to Microsoft.Network/dnsResolvers
  - Default subnet name: 'snet-dns-outbound'
- On-premise network connectivity established (ExpressRoute or VPN)
- On-premise DNS server IP addresses

## Quick Start

### Using Azure CLI

```bash
az deployment group create \
  --resource-group <your-resource-group> \
  --template-file template.json \
  --parameters \
    vnetName=<your-vnet-name> \
    subnetName=<your-subnet-name> \
    onPremDatabaseIp=<database-ip> \
    ... (see Parameters section)
```

### Using Azure Portal

1. Go to Azure Portal
2. Navigate to "Deploy a custom template"
3. Click "Build your own template in the editor"
4. Upload `template.json`
5. Fill in the required parameters
6. Review and create

## Parameters

### Required Parameters

- **vnetName**: Name of your Virtual Network
- **vnetResourceGroup**: Resource group containing the VNet
- **subnetName**: Name of the subnet for Private Link Service
- **onPremDatabaseIP**: Private IP of on-premise database
- **onPremDNSServerIP1**: IP of first on-premise DNS server
- **onPremDNSServerIP2**: IP of second on-premise DNS server
- **onPremDomainName**: Internal DNS domain (e.g., corp.local)

### Optional Parameters

- **databasePort**: Database port (default: 1433 for SQL Server, use 3306 for MySQL, 1521 for Oracle)
- **privateLinkServiceAlias**: Alias for Private Link Service (default: snowflake-pls)
- **dnsResolverSubnetName**: DNS resolver subnet name (default: snet-dns-outbound)
- **location**: Azure region (default: resource group location)

## Outputs

After deployment completes, note these important outputs:

- **privateLinkServiceId**: Provide this to Snowflake administrator
- **privateLinkServiceAlias**: Provide this to Snowflake administrator
- **loadBalancerPrivateIP**: Private IP of the load balancer
- **dnsResolverOutboundEndpointId**: DNS resolver endpoint ID (for troubleshooting)
- **dnsForwardingRulesetId**: DNS forwarding ruleset ID (for troubleshooting)

## Monitoring

Check deployment status:

```bash
az deployment group show \
  --resource-group <your-resource-group> \
  --name <deployment-name>
```

View deployment operations:

```bash
az deployment operation group list \
  --resource-group <your-resource-group> \
  --name <deployment-name>
```

## Validation

Before deployment, validate the template:

```bash
az deployment group validate \
  --resource-group <your-resource-group> \
  --template-file template.json \
  --parameters @parameters.json
```

## Troubleshooting

### Deployment Fails

1. Check deployment operations for specific errors
2. Verify all parameter values are correct
3. Ensure subscription has necessary permissions
4. Check resource provider registrations
5. Verify DNS resolver subnet exists and is delegated to Microsoft.Network/dnsResolvers

### Private Link Not Working

1. Verify load balancer backend health
2. Check NSG rules allow traffic
3. Confirm Private Link Service is in "Ready" state
4. Validate Snowflake subscription ID is correct

### DNS Resolution Issues

1. Verify DNS resolver is provisioned successfully
2. Check forwarding ruleset is linked to VNet
3. Confirm on-premise DNS servers are reachable
4. Test DNS resolution from Azure VMs in the VNet
5. Verify domain name ends with dot in forwarding rule

## Best Practices

1. **Use Parameter Files**: Create a `parameters.json` file for reusable deployments
2. **Test in Dev**: Deploy to development environment first
3. **Tag Resources**: Add appropriate tags for cost tracking
4. **Document IPs**: Keep record of all IP addresses used

## Example Parameters File

Create `parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "vnetName": { "value": "my-vnet" },
    "subnetName": { "value": "privatelink-subnet" },
    "onPremDatabaseIp": { "value": "192.168.1.10" },
    ...
  }
}
```

Then deploy with:

```bash
az deployment group create \
  --resource-group <your-rg> \
  --template-file template.json \
  --parameters @parameters.json
```

## Cleanup

To delete all deployed resources, delete the resource group or individual resources:

```bash
# Delete individual resources
az network private-link-service delete \
  --resource-group <your-resource-group> \
  --name snowflake-onprem-pls

az network lb delete \
  --resource-group <your-resource-group> \
  --name snowflake-onprem-slb

az network dns-resolver delete \
  --resource-group <your-resource-group> \
  --name dns-resolver-hub

az network nsg delete \
  --resource-group <your-resource-group> \
  --name snowflake-onprem-nsg
```

**Warning**: This will permanently delete all resources. Ensure you have backups.

## Support

For issues or questions:
1. Review the main documentation in `docs/04_azure_implementation.md`
2. Check Azure ARM template documentation
3. Verify parameters match your infrastructure

## References

- [Azure ARM Templates Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/)
- [Azure Private Link Documentation](https://docs.microsoft.com/en-us/azure/private-link/)
- [Snowflake External Access Integration](https://docs.snowflake.com/en/sql-reference/sql/create-external-access-integration)

