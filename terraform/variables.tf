variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "tenant_id" {
  description = "Azure Tenant ID"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name for storage account"
  type        = string
  default     = "rg-github-archives"
}

variable "location" {
  description = "Azure Region"
  type        = string
  default     = "westeurope"
}

variable "storage_account_name" {
  description = "Globally-unique storage account name"
  type        = string
  default     = "ghrepoarchive123"
}

variable "container_name" {
  description = "Blob container name"
  type        = string
  default     = "security-backups"
}
