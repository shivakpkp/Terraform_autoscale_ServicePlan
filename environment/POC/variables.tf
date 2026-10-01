variable "location" {
  description = "location"
  default     = "canadacentral"
}

variable "resource_group_name" {
  description = "resource group name"
  default     = "rg-autoscale"
}

variable "automation_account" {
  description = "automation account name"
  type = map(object({
    name     = string
    sku_name = string
    identity = string
  }))
  default = {
    poc-automation-account = {
      name     = "poc-automation-account"
      sku_name = "Basic"
      identity = "SystemAssigned"
    }
  }
}


variable "automation_account_runbook" {
  description = "powershell runbook"
  type = map(object({
    name         = string
    script_path  = string
    runbook_type = optional(string)
    log_verbose  = optional(bool)
    log_progress = optional(bool)
  }))
}


variable "action_groups" {
  description = "action group name"
  type = map(object({
    name       = string
    short_name = string
    runbook = list(object({
      name                = string
      runbook_name        = string
      webhook_resource_id = string
      service_uri         = string
      schema              = bool
    }))
    email = list(object({
      name          = string
      email_address = string
    }))
  }))
}

variable "Serviceplans" {
  description = "service plan names"
  type        = map(string)
}

variable "metric_alerts" {
  description = "metric alert name"
  type = map(object({
    name                = string
    resource_group_name = string
    # scoped_resource_id  = string
    metric_namespace = string
    metric_name      = string
    aggregation      = string
    operator         = string
    threshold        = number
    severity         = number
    frequency        = string
    window_size      = string
    # action_group_id     = string
  }))
  default = {
    Cpu_alert_scaleup = {
      name                = "Cpu_alert"
      resource_group_name = "rg-autoscale-terraform"
      metric_namespace    = "Microsoft.Web/serverFarms"
      metric_name         = "CpuPercentage"
      aggregation         = "Average"
      operator            = "GreaterThan"
      threshold           = 40
      severity            = 2
      frequency           = "PT1M"
      window_size         = "PT5M"
    },
    Memory_alert_scaleup = {
      name                = "Memory_alert"
      resource_group_name = "rg-autoscale-terraform"
      metric_namespace    = "Microsoft.Web/serverFarms"
      metric_name         = "MemoryPercentage"
      aggregation         = "Average"
      operator            = "GreaterThan"
      threshold           = 40
      severity            = 2
      frequency           = "PT1M"
      window_size         = "PT5M"
    },
    Cpu_alert_scaledown = {
      name                = "Cpu_alert"
      resource_group_name = "rg-autoscale-terraform"
      metric_namespace    = "Microsoft.Web/serverFarms"
      metric_name         = "CpuPercentage"
      aggregation         = "Average"
      operator            = "LessThan"
      threshold           = 20
      severity            = 2
      frequency           = "PT1M"
      window_size         = "PT5M"
    },
    Memory_alert_scaledown = {
      name                = "Memory_alert"
      resource_group_name = "rg-autoscale-terraform"
      metric_namespace    = "Microsoft.Web/serverFarms"
      metric_name         = "MemoryPercentage"
      aggregation         = "Average"
      operator            = "LessThan"
      threshold           = 20
      severity            = 2
      frequency           = "PT1M"
      window_size         = "PT5M"
    }
  }
}

variable "tags" {
  description = "tags"
  type        = map(string)
}

