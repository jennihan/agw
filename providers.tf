provider "azurerm" {
  features {}
  
  #client_id = "8a5a6080-7c09-454a-b7bc-133be0be0e6f"
  #client_secret = "fY58Q~4tO8G4PW1DhnVet5a1gUNnpq9zKJa8Zdl3"
  subscription_id = "4105419f-e724-4a4b-89f4-0cee686b07f1"
  #tenant_id = "bc903af4-9e34-49de-ac79-1187f7413cfe"
}


terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.59.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1.0"
    }
    
  }
  required_version = ">= 0.15.0"

  experiments = [module_variable_optional_attrs]
}

