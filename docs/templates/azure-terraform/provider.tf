# Terraform and Provider Configuration

terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.30" # Minimum version for DNS resolver support
    }
  }

  # Optional: Configure remote state backend
  # Uncomment and configure based on your needs
  #
  # backend "azurerm" {
  #   resource_group_name  = "terraform-state-rg"
  #   storage_account_name = "tfstatestorage"
  #   container_name       = "tfstate"
  #   key                  = "snowflake-privatelink.tfstate"
  # }
}

provider "azurerm" {
  features {}
}

