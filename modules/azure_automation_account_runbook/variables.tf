# =============================================================================
# Module: runbook — Variables
# =============================================================================

variable "name" {
  description = "Name of the Azure Automation Runbook"
  type        = string
}

variable "location" {
  description = "Azure region — must match the parent Automation Account's region"
  type        = string
}

variable "automation_account_name" {
  description = "Name of the parent Automation Account"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the Automation Account"
  type        = string
}

variable "script_path" {
  description = "Absolute or relative path to the .ps1 runbook script file"
  type        = string
}

variable "runbook_type" {
  description = "Runbook type. PowerShell72 uses PowerShell 7.2 runtime for modern Az module support."
  type        = string
  default     = "PowerShell72"
}

variable "log_verbose" {
  description = "Enable verbose logging in the runbook output stream"
  type        = bool
  default     = true
}

variable "log_progress" {
  description = "Enable progress logging in the runbook output stream"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to the runbook resource"
  type        = map(string)
  default     = {}
}

variable "webhook_name" {
  description = "Name of the Azure Automation Webhook"
  type        = string
}

variable "webhook_expiry_time" {
  description = "Expiry time of the Azure Automation Webhook in RFC3339 format (e.g., 2030-01-01T00:00:00Z)"
  type        = string
  default     = "2030-01-01T00:00:00Z"
}