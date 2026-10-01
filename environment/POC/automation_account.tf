module "automation_account" {
  for_each            = var.automation_account
  source              = "../../modules/azure_automation_account"
  location            = var.location
  resource_group_name = var.resource_group_name
  name                = var.automation_account[each.key].name
  sku_name            = var.automation_account[each.key].sku_name
  identity            = var.automation_account[each.key].identity
}