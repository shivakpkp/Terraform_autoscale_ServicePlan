# =============================================================================
# Module: runbook
# =============================================================================
# Description: Publishes the PowerShell 7.2 runbook script to the Automation
#              Account. The script file is read from disk at plan/apply time
#              using the file() function, so the runbook content is fully
#              version-controlled alongside Terraform.
#
# PowerShell72 runtime is used (not PowerShell5) because:
#   - Az module cmdlets are actively tested against PS7
#   - Better structured error handling with $ErrorActionPreference = 'Stop'
#   - Faster startup time in Azure Automation sandboxes
# =============================================================================

resource "azurerm_automation_runbook" "this" {
  name                    = var.name
  location                = var.location
  resource_group_name     = var.resource_group_name
  automation_account_name = var.automation_account_name
  runbook_type            = var.runbook_type
  log_verbose             = var.log_verbose
  log_progress            = var.log_progress
  tags                    = var.tags

  # Inline content — Terraform will update the runbook when the script file changes.
  # The file() path is resolved relative to where 'terraform apply' is executed.
  content = file(var.script_path)

  description = "POC runbook: scales App Service Plan SKUs up or down based on tags. Mode parameter controls direction."
}

resource "azurerm_automation_webhook" "this" {
  name                    = var.webhook_name
  resource_group_name     = var.resource_group_name
  automation_account_name = var.automation_account_name
  runbook_name            = azurerm_automation_runbook.this.name
  expiry_time             = var.webhook_expiry_time
  enabled                 = true
}
