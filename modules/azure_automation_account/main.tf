# =============================================================================
# Module: automation_account
# =============================================================================
# Description: Provisions an Azure Automation Account with a System-Assigned
#              Managed Identity. The managed identity is used by the runbook
#              to authenticate to Azure APIs (Connect-AzAccount -Identity)
#              without storing any credentials. RBAC rights are granted
#              separately in the rbac module.
# =============================================================================

resource "azurerm_automation_account" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = var.sku_name
  tags                = var.tags

  # System-assigned identity provides an automatically rotated service principal
  # scoped to this Automation Account — no secret management required.
  identity {
    type = var.identity
  }
}
