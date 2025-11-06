# Infrastructure as Code Templates

This directory contains Infrastructure as Code (IaC) templates for deploying Snowflake PrivateLink connectivity to on-premise databases.

## Overview

Choose the template that matches your cloud provider and preferred deployment method:

### AWS Deployments
- **[aws-cloudformation/](aws-cloudformation/)** - AWS CloudFormation template (declarative YAML)
- **[aws-terraform/](aws-terraform/)** - Terraform configuration for AWS (HCL)

### Azure Deployments
- **[azure-arm/](azure-arm/)** - Azure Resource Manager template (JSON)
- **[azure-terraform/](azure-terraform/)** - Terraform configuration for Azure (HCL)

## Quick Comparison

| Template | Cloud | Format | Best For |
|----------|-------|--------|----------|
| **aws-cloudformation** | AWS | YAML | AWS-native deployments, AWS Console users |
| **aws-terraform** | AWS | HCL | Multi-cloud shops, GitOps workflows |
| **azure-arm** | Azure | JSON | Azure-native deployments, Azure Portal users |
| **azure-terraform** | Azure | HCL | Multi-cloud shops, GitOps workflows |

## What Gets Deployed

### AWS Infrastructure
- **Network Load Balancer (NLB)** - Internal load balancer for database traffic
- **VPC Endpoint Service** - PrivateLink service for Snowflake connectivity
- **Route 53 Resolver** - Hybrid DNS for on-premise name resolution
- **Network ACLs** - Layer 4 security controls
- **Transit Gateway Routes** - Routing to on-premise network

### Azure Infrastructure
- **Standard Load Balancer** - Internal load balancer for database traffic
- **Private Link Service** - Private endpoint service for Snowflake connectivity
- **DNS Private Resolver** - Hybrid DNS for on-premise name resolution
- **Network Security Group** - Layer 4 security controls
- **Virtual Network** - Isolated network environment

## Prerequisites

### General Requirements
- On-premise database with known IP address and port
- Network connectivity between cloud and on-premise (VPN/ExpressRoute/Direct Connect)
- On-premise DNS servers accessible from cloud
- Internal domain name for on-premise resources

### AWS-Specific
- Existing VPC with at least 2 subnets in different Availability Zones
- Transit Gateway configured and attached to VPC
- Snowflake VPC CIDR block (obtain from Snowflake Support)
- Snowflake AWS account ID (obtain from Snowflake Support)

### Azure-Specific
- Existing Virtual Network
- Snowflake Azure subscription ID (obtain from Snowflake Support)
- Appropriate Azure region selected

## Getting Started

1. **Choose your template** based on cloud provider and deployment method
2. **Read the template-specific README** in its directory
3. **Prepare your parameters** (VPC/VNet IDs, IP addresses, etc.)
4. **Deploy the template** using CLI or Portal/Console
5. **Note the outputs** (VPC Endpoint Service Name or Private Link Service ID)
6. **Provide outputs to Snowflake** administrator to complete connection

## Terraform Projects

Both Terraform configurations are production-ready with:
- ✅ Proper file structure (`main.tf`, `variables.tf`, `outputs.tf`, `provider.tf`)
- ✅ Comprehensive variable definitions with descriptions
- ✅ Example `.tfvars` files for easy configuration
- ✅ Detailed README with step-by-step instructions
- ✅ `.gitignore` files to prevent committing secrets
- ✅ Validated configurations (`terraform validate` passed)

### Terraform Workflow

```bash
# 1. Navigate to template directory
cd aws-terraform/  # or azure-terraform/

# 2. Copy and edit example variables
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars

# 3. Initialize Terraform
terraform init

# 4. Review planned changes
terraform plan

# 5. Apply configuration
terraform apply

# 6. Note outputs
terraform output
```

## Security Considerations

### Network Security
- All templates deploy internal load balancers (not internet-facing)
- Network ACLs/NSGs restrict traffic to necessary ports only
- PrivateLink ensures traffic never traverses public internet

### Access Control
- VPC Endpoint Services require manual acceptance
- Private Link Services restricted to Snowflake subscription only
- DNS resolvers limited to specific on-premise DNS servers

### Best Practices
1. **Least Privilege**: Use minimum necessary permissions for deployment
2. **Separate Accounts**: Consider separate AWS/Azure accounts for production
3. **Audit Logs**: Enable CloudTrail/Activity Logs for all resources
4. **Encryption**: All PrivateLink traffic is encrypted in transit
5. **Regular Reviews**: Periodically review and update security rules

## Validation

All templates have been validated:
- ✅ **Terraform**: `terraform validate` passes
- ✅ **CloudFormation**: Valid YAML syntax
- ✅ **ARM**: Valid JSON syntax

## Support & Documentation

### Template-Specific Help
Each template directory contains a detailed README with:
- Prerequisites
- Step-by-step deployment instructions
- Parameter descriptions
- Troubleshooting guides
- Cleanup procedures

### Main Documentation
- **[AWS Implementation Guide](../03_aws_implementation.md)** - Detailed AWS setup walkthrough
- **[Azure Implementation Guide](../04_azure_implementation.md)** - Detailed Azure setup walkthrough
- **[SPCS Setup Guide](../05_spcs_setup.md)** - Snowflake configuration

### External Resources
- [Snowflake External Access Integration Docs](https://docs.snowflake.com/en/sql-reference/sql/create-external-access-integration)
- [AWS PrivateLink Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/)
- [Azure Private Link Documentation](https://docs.microsoft.com/en-us/azure/private-link/)

## Version History

- **v1.0.0** - Initial release with CloudFormation and ARM templates
- **v1.1.0** - Added Terraform configurations for both clouds
- **v1.2.0** - Restructured into separate directories, added comprehensive READMEs

## Contributing

When updating templates:
1. Validate syntax before committing
2. Update corresponding README
3. Test in development environment
4. Document any breaking changes

## License

These templates are provided as-is for use in deploying Snowflake connectivity infrastructure.

---

**Last Updated**: November 2025
**Status**: Production Ready ✓
