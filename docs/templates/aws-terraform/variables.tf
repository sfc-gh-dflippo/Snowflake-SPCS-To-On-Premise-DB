variable "aws_region" {
  type        = string
  description = "The AWS region to deploy resources in. Example: us-east-1"
}

variable "vpc_id" {
  type        = string
  description = "REQUIRED: The ID of the VPC. Find in: AWS VPC Console -> Your VPCs. Example: vpc-0123456789abcdef0"
}

variable "subnet_id_1" {
  type        = string
  description = "REQUIRED: The ID of the first private subnet (AZ 1). Find in: VPC Console -> Subnets. Must be in a different AZ than subnet_id_2. Example: subnet-0123abc..."
}

variable "subnet_id_2" {
  type        = string
  description = "REQUIRED: The ID of the second private subnet (AZ 2). Find in: VPC Console -> Subnets. Must be in a different AZ than subnet_id_1. Example: subnet-0456def..."
}

variable "route_table_id_1" {
  type        = string
  description = "REQUIRED: The Route Table ID for subnet_id_1. Find in: VPC Console -> Subnets -> (Select subnet_id_1) -> Route Table tab. Example: rtb-0123abc..."
}

variable "route_table_id_2" {
  type        = string
  description = "REQUIRED: The Route Table ID for subnet_id_2. Find in: VPC Console -> Subnets -> (Select subnet_id_2) -> Route Table tab. Example: rtb-0456def..."
}

variable "on_prem_database_ip" {
  type        = string
  description = "REQUIRED: The private IP address of the on-premise SQL Server. Find by: Ask your Database Administrator (DBA). Example: 10.50.10.100"
}

variable "on_prem_cidr" {
  type        = string
  description = "REQUIRED: The CIDR block of your on-premise network (where the database lives). Find by: Ask your Network Administrator. Example: 10.50.0.0/16"
}

variable "on_prem_domain_name" {
  type        = string
  description = "REQUIRED: The internal DNS domain to forward queries to. Find by: Ask your Network Administrator. (Default is a common example)."
  default     = "corp.local"
}

variable "on_prem_dns_server_ip_1" {
  type        = string
  description = "REQUIRED: The IP address of the first on-premise DNS server (e.g., Domain Controller). Find by: Ask your Network Administrator. Example: 10.50.1.10"
}

variable "on_prem_dns_server_ip_2" {
  type        = string
  description = "REQUIRED: The IP address of the second on-premise DNS server. Find by: Ask your Network Administrator. Example: 10.50.1.11"
}

variable "database_port" {
  type        = number
  description = "REQUIRED: The port of the on-premise SQL Server. (Default is 1433 for SQL Server)."
  default     = 1433
}

variable "transit_gateway_id" {
  type        = string
  description = "REQUIRED: The ID of the Transit Gateway that connects this VPC to on-prem. Find in: VPC Console -> Transit Gateways. Example: tgw-0123abc..."
}

variable "snowflake_vpc_cidr" {
  type        = string
  description = "CRITICAL: The CIDR block of the Snowflake VPC. Find by: Contact Snowflake Support. This is NOT in your AWS account. Example: 54.10.0.0/24"
}

