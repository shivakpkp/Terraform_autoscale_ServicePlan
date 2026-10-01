# =============================================================================
# Module: runbook — Outputs
# =============================================================================

output "id" {
  description = "Resource ID of the Automation Runbook"
  value       = azurerm_automation_runbook.this.id
}

output "name" {
  description = "Name of the Automation Runbook"
  value       = azurerm_automation_runbook.this.name
}

output "content_sha256" {
  description = "SHA256 of the script file at plan/apply time; use to replace dependent job schedules when runbook content changes (Azure can drop schedule links on publish)."
  value       = filesha256(var.script_path)
}

output "webhook_id" {
  description = "Resource ID of the Automation Webhook"
  value       = azurerm_automation_webhook.this.id
}

output "webhook_uri" {
  description = "Service URI of the Automation Webhook (the HTTPS endpoint that triggers the runbook)"
  value       = azurerm_automation_webhook.this.uri
}
