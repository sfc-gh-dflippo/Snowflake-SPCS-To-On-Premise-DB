# Terraform and Provider Configuration

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Optional: Configure remote state backend
  # Uncomment and configure based on your needs
  #
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "snowflake-privatelink/terraform.tfstate"
  #   region         = "us-west-2"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

provider "aws" {
  region = var.aws_region

  # Optional: Add default tags to all resources
  default_tags {
    tags = {
      Project     = "Snowflake-PrivateLink"
      ManagedBy   = "Terraform"
      Environment = "Production"
    }
  }
}

