terraform {
  backend "azurerm" {
    resource_group_name  = "rg-github-archives"
    storage_account_name = "ghrepoarchive123"
    container_name       = "security-backups"
    key                  = "terraform.tfstate"
  }
}
