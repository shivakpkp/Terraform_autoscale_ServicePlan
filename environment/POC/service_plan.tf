data "azurerm_service_plan" "this" {
  for_each            = var.Serviceplans
  name                = each.key
  resource_group_name = each.value
}