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
  backend "azurerm" {
    use_azuread_auth = true
  }
}

# Configure the Microsoft Azure provider with the required authentication details.
provider "azurerm" {
  features {}

}

provider "azapi" {
  features {}
  
}