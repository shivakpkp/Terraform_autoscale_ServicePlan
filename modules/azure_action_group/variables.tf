# =============================================================================
# Module: action_group — Variables
# =============================================================================


variable "resource_group_name" {
  description = "Resource group in which to place the Action Group"
  type        = string
}

variable "action_group_name" {
  description = "Name of the Action Group"
  type        = string
}

variable "action_group_short_name" {
  description = "Short name of the Action Group (used in alert emails)"
  type        = string
}


variable "runbook" {
  description = "List of runbook receivers for the Action Group"
  type = list(object({
    name                  = string
    automation_account_id = string
    runbook_name          = string
    webhook_resource_id   = string
    service_uri           = string
    schema                = bool
  }))
}

variable "email" {
  description = "List of email receivers for the Action Group"
  type = list(object({
    name          = string
    email_address = string
  }))
}

variable "tags" {
  description = "Tags to apply to the Action Group"
  type        = map(string)
  default     = {}
}

