module "action_group" {
  for_each = var.action_groups

  source = "../../modules/azure_action_group"

  resource_group_name     = var.resource_group_name
  action_group_name       = each.value.name
  action_group_short_name = each.value.short_name

  runbook = [
    for runbook in each.value.runbook : merge(
      runbook,
      {
        automation_account_id = module.automation_account[
          "poc-automation-account"
        ].id

        webhook_resource_id = moduSle.automation_account_runbook[
          runbook.runbook_name
        ].webhook_id

        service_uri = module.automation_account_runbook[
          runbook.runbook_name
        ].webhook_uri
      }
    )
  ]

  email = each.value.email

  tags = var.tags
}