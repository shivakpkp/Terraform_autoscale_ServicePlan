# Terraform configuration for the AzureRM provider version used by this deployment.
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=5.0.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0" # Ensures you have up-to-date API support
    }
  }
}

# Configure the Microsoft Azure provider with the required authentication details.
provider "azurerm" {
  features {}

  client_id       = secret.client_id
  client_secret   = secret.secret
  tenant_id       = secret.tenant_id
  subscription_id = secret.subscription_id
}

provider "azapi" {

  client_id       = secret.client_id
  client_secret   = secret.secret
  tenant_id       = secret.tenant_id
  subscription_id = secret.subscription_id
}