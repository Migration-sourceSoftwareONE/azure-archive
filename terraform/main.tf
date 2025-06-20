terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"               # Backend for Terraform state (must be pre-created)
    storage_account_name = "tfstatestorageaccount123"    # Backend for Terraform state (must be pre-created)
    container_name       = "tfstate"                  # Backend for Terraform state (must be pre-created)
    key                  = "terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_storage_account" "storage" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  allow_blob_public_access = false
}

resource "azurerm_storage_container" "container" {
  name                  = var.container_name
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

output "storage_account_name" {
  value = azurerm_storage_account.storage.name
}

output "storage_account_primary_key" {
  value     = azurerm_storage_account.storage.primary_access_key
  sensitive = true
}

output "container_name" {
  value = azurerm_storage_container.container.name
}
