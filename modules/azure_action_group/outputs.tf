# =============================================================================
# Module: action_group — Outputs
# =============================================================================

output "id" {
  description = "Resource ID of the Action Group (referenced by metric alert modules)"
  value       = azurerm_monitor_action_group.this.id
}

output "name" {
  description = "Name of the Action Group"
  value       = azurerm_monitor_action_group.this.name
}
