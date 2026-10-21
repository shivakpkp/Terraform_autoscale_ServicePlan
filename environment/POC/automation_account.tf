module "automation_account" {
  for_each            = var.automation_account
  source              = "../../modules/azure_automation_account"
  location            = var.location
  resource_group_name = var.resource_group_name
  name                = var.automation_account[each.key].name
  sku_name            = var.automation_account[each.key].sku_name
  identity            = var.automation_account[each.key].identity
}

resource "azurerm_role_assignment" "sub_access" {
  for_each = module.automation_account
  # Set the scope to the entire subscription ID
  scope                = "/subscriptions/${var.subscription_id}"
  
  # Define the built-in or custom role name
  role_definition_name = "Contributor" # You can change this to any other role as needed
  
  # Reference the dynamically generated principal ID from the VM's identity block
  principal_id         = each.value.principal_id
  principal_type       = "ServicePrincipal"
}