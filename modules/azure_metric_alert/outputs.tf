# =============================================================================
# Module: metric_alert — Outputs
# =============================================================================

output "id" {
  description = "Resource ID of the Metric Alert"
  value       = azurerm_monitor_metric_alert.this.id
}

output "name" {
  description = "Name of the Metric Alert"
  value       = azurerm_monitor_metric_alert.this.name
}
