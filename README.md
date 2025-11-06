# Architecting Secure, Private On-Premise Connectivity for Snowflake Snowpark Container Services on AWS and Azure

## ⚠️ Status: DRAFT - IN THE PROCESS OF BEING VALIDATED

**Caveat Emptor:** Although this document makes every effort to be accurate, cloud architectures are fluid and users are encouraged to review the footnotes directly in case things have changed.

## 📋 Table of Contents

### Documentation

1. **[Executive Summary](docs/01_executive_summary.md)**
   - Problem Statement
   - Solution Overview
   - Key Technologies

2. **[Architectural Pattern](docs/02_architectural_pattern.md)**
   - The Connectivity Chain
   - The Parallel DNS Resolution Chain
   - Snowflake External Access Integrations (EAI)
   - Comparison of Core Services in AWS and Azure Solutions

3. **[AWS Implementation Guide](docs/03_aws_implementation.md)**
   - Establishing the AWS Hybrid Network Foundation
   - Configuring Snowflake for Outbound Private Connectivity to AWS
   - End-to-End Routing, Security, and Debugging/Validation

4. **[Azure Implementation Guide](docs/04_azure_implementation.md)**
   - Establishing the Azure Hybrid Network Foundation
   - Configuring Snowflake for Outbound Private Connectivity to Azure
   - End-to-End Routing, Security, and Validation

5. **[SPCS Setup and Validation](docs/05_spcs_setup.md)**
   - Deploying and Configuring an Openflow Snowpark Container Service
   - Initial Openflow DB Setup
   - Creating Deployments and Runtime Environments

6. **[References](docs/06_references.md)**
   - Snowflake Documentation
   - AWS Documentation and Resources
   - Azure Documentation and Resources
   - Third-Party Articles and Blogs

### Infrastructure Templates

The [`docs/templates/`](docs/templates/) directory contains ready-to-deploy infrastructure-as-code templates for both AWS and Azure implementations:

#### AWS Templates
- **[AWS CloudFormation Template](docs/templates/aws_cloudformation.yaml)** - Complete CloudFormation stack for AWS deployment
- **[AWS Terraform Main](docs/templates/aws_terraform_main.tf)** - Terraform main configuration for AWS
- **[AWS Terraform Variables](docs/templates/aws_terraform_variables.tf)** - Variable definitions for AWS Terraform
- **[Terraform Variables Example](docs/templates/terraform.tfvars.example)** - Example values file for Terraform

#### Azure Templates
- **[Azure ARM Template](docs/templates/azure_arm.json)** - Azure Resource Manager template for Azure deployment
- **[Azure Terraform](docs/templates/azure_terraform.tf)** - Terraform configuration for Azure

See the [Templates README](docs/templates/README.md) for detailed usage instructions.

## 🎯 Overview

This guide provides a comprehensive architectural blueprint and step-by-step implementation for establishing secure, private connectivity between Snowflake Snowpark Container Services (SPCS) and on-premise databases. The solution eliminates the need to expose sensitive on-premise systems to the public internet by leveraging native cloud provider networking capabilities.

### Key Features

- **End-to-End Private Connectivity**: All traffic remains within cloud provider backbones and private networks
- **Hybrid DNS Resolution**: Seamless name resolution across cloud and on-premise environments
- **Multi-Cloud Support**: Parallel implementations for both AWS and Azure
- **Infrastructure as Code**: Ready-to-deploy CloudFormation, Terraform, and ARM templates
- **Comprehensive Security**: Detailed security group, NACL, and NSG configurations

### Use Cases

- Connecting SPCS containers to on-premise Microsoft SQL Server
- Querying Oracle, Teradata, and other enterprise databases from Snowflake
- Running Openflow data integration pipelines with on-premise data sources
- Machine learning model training using hybrid data sources

## 🚀 Quick Start

1. **Choose Your Cloud Platform**: Select either [AWS](docs/03_aws_implementation.md) or [Azure](docs/04_azure_implementation.md)
2. **Review Architecture**: Understand the [Architectural Pattern](docs/02_architectural_pattern.md)
3. **Deploy Infrastructure**: Use the provided [templates](docs/templates/) to set up networking components
4. **Configure Snowflake**: Follow the SPCS setup guide to create External Access Integrations
5. **Validate**: Test connectivity and security configurations

## 📚 Additional Resources

- [Snowflake SPCS Documentation](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/overview)
- [AWS PrivateLink Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/)
- [Azure Private Link Documentation](https://learn.microsoft.com/en-us/azure/private-link/)

## 📄 License

See [LICENSE](LICENSE) file for details.

## 🤝 Contributing

This is an evolving document. As cloud architectures change and best practices emerge, contributions and updates are welcome.

---

**Last Updated**: November 2025
