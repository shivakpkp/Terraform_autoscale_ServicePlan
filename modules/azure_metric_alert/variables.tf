# =============================================================================
# Module: metric_alert — Variables
# =============================================================================
# This module is instantiated twice in main.tf:
#   - Once scoped to the App Service Plan (Microsoft.Web/serverfarms)
#   - Once scoped to the Web App (Microsoft.Web/sites)

variable "name" {
  description = "Name of the Azure Monitor Metric Alert"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group in which to place the Metric Alert"
  type        = string
}

variable "scoped_resource_id" {
  description = "Resource ID of the target resource being monitored (ASP or Web App)"
  type        = string
}

variable "metric_namespace" {
  description = "Azure Monitor metric namespace (e.g. 'Microsoft.Web/serverfarms' or 'Microsoft.Web/sites')"
  type        = string
}

variable "metric_name" {
  description = "Metric name within the namespace (e.g. 'CpuPercentage' for ASP, 'CpuTime' for Web App)"
  type        = string
}

variable "threshold" {
  description = "Threshold value that triggers the alert (percentage for CpuPercentage, CPU-seconds Total for CpuTime, etc.)"
  type        = number
  default     = 35
}

variable "action_group_id" {
  description = "Resource ID of the Action Group to invoke when the alert fires"
  type        = string
}

variable "aggregation" {
  description = "Aggregation type for the metric (Average is standard for CPU metrics)"
  type        = string
  default     = "Average"
}

variable "operator" {
  description = "Comparison operator for the threshold check"
  type        = string
  default     = "GreaterThan"
}

variable "window_size" {
  description = "Time window over which the metric is aggregated (ISO 8601 duration)"
  type        = string
  default     = "PT5M"
}

variable "frequency" {
  description = "How often the alert condition is evaluated (ISO 8601 duration)"
  type        = string
  default     = "PT1M"
}

variable "severity" {
  description = "Alert severity (0=Critical, 1=Error, 2=Warning, 3=Informational, 4=Verbose)"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Tags to apply to the Metric Alert"
  type        = map(string)
  default     = {}
}
