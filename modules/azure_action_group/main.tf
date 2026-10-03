# =============================================================================
# Module: action_group
# =============================================================================
# Description: Provisions an Azure Automation Webhook and an Azure Monitor
#              Action Group with two receivers:
#   1. email_receiver              : alert email to the POC notification address
#   2. automation_runbook_receiver : triggers the scale-up runbook via webhook
#
# Why a real azurerm_automation_webhook is required:
#   The automation_runbook_receiver block needs a real webhook_resource_id and
#   a real service_uri (the per-webhook HTTPS endpoint). Using a synthesized ID
#   causes Terraform apply to succeed but the alert trigger to silently fail at
#   runtime because Azure cannot resolve the fake resource ID to a callable URI.
#
# Alert email via Action Group covers the scale-up alert path.
# All other outcomes (scale-down, no-op, failure) are emailed by the runbook
# itself using Send-MailMessage (configured in runbook Automation variables).
# =============================================================================

# ---------------------------------------------------------------------------
# Webhook: created so the Action Group has a real, callable URI for the runbook.
# Parameters are passed here; Azure passes them to the runbook when it fires.
# Expiry is set far in the future — update before 2030 in a production system.
#
# IMPORTANT: Azure does not allow changing which runbook a webhook targets (in-place
# update returns 400 "Property 'runbook' cannot be updated."). The webhook *name*
# therefore includes a stable hash of var.runbook_name so when the target runbook
# changes, Terraform replaces the webhook (destroy + create) instead of PATCHing it.
# ---------------------------------------------------------------------------


resource "azurerm_monitor_action_group" "this" {
  name                = var.action_group_name
  resource_group_name = var.resource_group_name
  short_name          = var.action_group_short_name

  dynamic "automation_runbook_receiver" {
    for_each = var.runbook
    content {
      name                    = automation_runbook_receiver.value.name
      automation_account_id   = automation_runbook_receiver.value.automation_account_id
      runbook_name            = automation_runbook_receiver.value.runbook_name
      webhook_resource_id     = automation_runbook_receiver.value.webhook_resource_id
      is_global_runbook       = true
      service_uri             = automation_runbook_receiver.value.service_uri
      use_common_alert_schema = automation_runbook_receiver.value.schema

    }
  }

  dynamic "email_receiver" {
    for_each = var.email
    content {
      name          = email_receiver.value.name
      email_address = email_receiver.value.email_address
    }
  }

  tags = var.tags
}