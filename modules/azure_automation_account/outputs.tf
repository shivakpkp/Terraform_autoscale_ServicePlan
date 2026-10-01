# =============================================================================
# Module: automation_account — Outputs
# =============================================================================

output "id" {
  description = "Resource ID of the Automation Account"
  value       = azurerm_automation_account.this.id
}

output "name" {
  description = "Name of the Automation Account"
  value       = azurerm_automation_account.this.name
}

output "principal_id" {
  description = "Object ID of the system-assigned managed identity — used to create RBAC assignments"
  value       = azurerm_automation_account.this.identity[0].principal_id
}

output "dsc_server_endpoint" {
  description = "DSC server endpoint URL (informational)"
  value       = azurerm_automation_account.this.dsc_server_endpoint
}
