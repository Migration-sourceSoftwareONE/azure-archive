provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

# Variables (you can also hardcode values if preferred)
variable "resource_group_name" {
  default = "rg-github-archives-mc"
}

variable "location" {
  default = "westeurope"
}

variable "storage_account_name" {
  default = "ghrepoarchive123-mc" # must be globally unique and lowercase
}

variable "container_name" {
  default = "security-backups-mc"
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# Storage Account
resource "azurerm_storage_account" "storage" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot" # Archive not available at account level
  min_tls_version          = "TLS1_2"
}

# Blob Container
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
