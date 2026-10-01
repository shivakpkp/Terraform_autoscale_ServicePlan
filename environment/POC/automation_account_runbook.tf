module "automation_account_runbook" {
  for_each                = var.automation_account_runbook
  source                  = "../../modules/azure_automation_account_runbook"
  name                    = each.value.name
  automation_account_name = module.automation_account["poc-automation-account"].name
  script_path             = each.value.script_path
  resource_group_name     = var.resource_group_name
  location                = var.location
  webhook_name            = "${each.value.name}-webhook"
  webhook_expiry_time     = "2030-01-01T00:00:00Z"
  tags                    = var.tags
  depends_on              = [module.automation_account]
}