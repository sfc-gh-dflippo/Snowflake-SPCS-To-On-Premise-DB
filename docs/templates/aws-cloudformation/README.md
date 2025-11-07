# AWS CloudFormation Template

This directory contains an AWS CloudFormation template for deploying Snowflake PrivateLink connectivity infrastructure.

## Overview

This CloudFormation stack creates:
- Network Load Balancer (NLB) with target group
- VPC Endpoint Service for PrivateLink
- Route 53 Resolver Outbound Endpoint
- DNS forwarding rules for on-premise resolution
- Network ACLs and security configurations

## Prerequisites

- AWS CLI configured with appropriate credentials
- AWS account with necessary permissions
- Existing VPC with appropriate subnets
- Transit Gateway connecting to on-premise network
- On-premise DNS servers accessible

## Quick Start

### Using AWS CLI

```bash
aws cloudformation create-stack \
  --stack-name snowflake-privatelink \
  --template-body file://stack.yaml \
  --parameters \
    ParameterKey=VpcId,ParameterValue=vpc-xxxxx \
    ParameterKey=SubnetId1,ParameterValue=subnet-xxxxx \
    ParameterKey=SubnetId2,ParameterValue=subnet-yyyyy \
    ParameterKey=RouteTableId1,ParameterValue=rtb-xxxxx \
    ParameterKey=RouteTableId2,ParameterValue=rtb-yyyyy \
    ParameterKey=OnPremDatabaseIP,ParameterValue=10.50.100.25 \
    ParameterKey=OnPremCidr,ParameterValue=10.50.0.0/16 \
    ParameterKey=OnPremDNSServerIP1,ParameterValue=10.50.1.10 \
    ParameterKey=OnPremDNSServerIP2,ParameterValue=10.50.1.11 \
    ParameterKey=TransitGatewayId,ParameterValue=tgw-xxxxx \
    ParameterKey=SnowflakeVpcCidr,ParameterValue=54.10.0.0/24
# Note: DatabasePort and OnPremDomainName use defaults (1433 and corp.local)
# Add them explicitly if your values differ from the defaults
```

### Using AWS Console

1. Go to AWS CloudFormation Console
2. Click "Create stack" → "With new resources"
3. Upload `stack.yaml`
4. Fill in the required parameters
5. Review and create

## Parameters

### Required Parameters

- **VpcId**: ID of your VPC
- **SubnetId1**: First subnet ID (must be in different AZ from SubnetId2)
- **SubnetId2**: Second subnet ID
- **RouteTableId1**: Route table ID for SubnetId1
- **RouteTableId2**: Route table ID for SubnetId2
- **OnPremDatabaseIP**: Private IP of on-premise database
- **OnPremCidr**: CIDR block of on-premise network
- **OnPremDomainName**: Internal DNS domain (e.g., corp.local)
- **OnPremDNSServerIP1**: IP of first on-premise DNS server
- **OnPremDNSServerIP2**: IP of second on-premise DNS server
- **TransitGatewayId**: Transit Gateway ID connecting to on-premise
- **SnowflakeVpcCidr**: Snowflake VPC CIDR (obtain from Snowflake Support)

### Optional Parameters

- **DatabasePort**: Database port (default: 1433 for SQL Server)

## Outputs

After stack creation, note these important outputs:

- **VpcEndpointServiceName**: Provide this to Snowflake administrator
- **VpcEndpointServiceId**: The VPC Endpoint Service ID
- **NLBDNSName**: DNS name of the Network Load Balancer

## Deployment Time

**Expected Duration:** 5-10 minutes

Component breakdown:
- Network Load Balancer: ~2-3 minutes
- VPC Endpoint Service: ~1 minute  
- Route 53 Resolver Endpoints: ~2-3 minutes
- Network ACL associations: <1 minute
- Route table updates: <1 minute

## Monitoring

Monitor stack creation progress:

```bash
aws cloudformation describe-stacks \
  --stack-name snowflake-privatelink \
  --query 'Stacks[0].StackStatus'
```

View stack events:

```bash
aws cloudformation describe-stack-events \
  --stack-name snowflake-privatelink
```

## Troubleshooting

### Stack Creation Fails

1. Check CloudFormation events for specific error
2. Verify all parameter values are correct
3. Ensure IAM permissions are sufficient
4. Check resource limits in your AWS account

### Connection Not Working

1. Verify NLB target health in EC2 Console
2. Check NACL rules allow traffic on database port
3. Confirm VPC Endpoint Service connection is accepted
4. Validate Route 53 resolver rules are active

## Cleanup

To delete all resources:

```bash
aws cloudformation delete-stack --stack-name snowflake-privatelink
```

**Warning**: This will permanently delete all resources. Ensure you have backups.

## Support

For issues or questions:
1. Review the main documentation in `docs/03_aws_implementation.md`
2. Check AWS CloudFormation documentation
3. Verify parameters match your infrastructure

## References

- [AWS CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)
- [AWS PrivateLink Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/)
- [Snowflake External Access Integration](https://docs.snowflake.com/en/sql-reference/sql/create-external-access-integration)

