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
- On-premise network connectivity established

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
- **onPremDatabaseIp**: Private IP of on-premise database
- **onPremDnsServer1**: IP of first on-premise DNS server
- **onPremDnsServer2**: IP of second on-premise DNS server
- **onPremDomainName**: Internal DNS domain (e.g., corp.local)
- **privateLinkServiceAlias**: Alias for Private Link Service

### Optional Parameters

- **databasePort**: Database port (default: 3306 for MySQL)
- **location**: Azure region (default: resource group location)

## Outputs

After deployment completes, note these important outputs:

- **privateLinkServiceId**: Provide this to Snowflake administrator
- **privateLinkServiceAlias**: Provide this to Snowflake administrator
- **loadBalancerPrivateIp**: Private IP of the load balancer

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

### Private Link Not Working

1. Verify load balancer backend health
2. Check NSG rules allow traffic
3. Confirm Private Link Service is in "Ready" state
4. Validate Snowflake subscription ID is correct

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

To delete all resources:

```bash
az deployment group delete \
  --resource-group <your-resource-group> \
  --name <deployment-name>
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

