# =============================================================================
# Module: automation_account — Variables
# =============================================================================

variable "name" {
  description = "Name of the Azure Automation Account"
  type        = string
}

variable "location" {
  description = "Azure region for the Automation Account"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group in which to place the Automation Account"
  type        = string
}

variable "sku_name" {
  description = "SKU for the Automation Account. 'Basic' is sufficient for runbooks and schedules."
  type        = string
  default     = "Basic"
}

variable "tags" {
  description = "Tags to apply to the Automation Account"
  type        = map(string)
  default     = {}
}

variable "identity" {
  description = "Type of identity to assign to the Automation Account. 'SystemAssigned' is recommended for runbooks."
  type        = string
  default     = "SystemAssigned"
}
