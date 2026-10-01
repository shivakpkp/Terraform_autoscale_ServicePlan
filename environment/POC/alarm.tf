module "alert" {
  source              = "../../modules/azure_metric_alert"
  for_each            = local.alert
  resource_group_name = var.resource_group_name
  name                = each.value.name
  scoped_resource_id  = each.value.scoped_resource_id
  metric_namespace    = each.value.metric_namespace
  metric_name         = each.value.metric_name
  aggregation         = each.value.aggregation
  operator            = each.value.operator
  threshold           = each.value.threshold
  severity            = each.value.severity
  frequency           = each.value.frequency
  window_size         = each.value.window_size
  action_group_id     = each.value.action_group_id

}


locals {
  alert = merge([
    for service_plan_key, service_plan in data.azurerm_service_plan.this : {
      for alert_name, alert in var.metric_alerts :
      "${service_plan_key}-${alert_name}" => {
        name                = "${service_plan_key}-${alert_name}"
        resource_group_name = alert.resource_group_name
        scoped_resource_id  = service_plan.id

        metric_namespace    = var.metric_alerts[alert_name].metric_namespace
        metric_name         = var.metric_alerts[alert_name].metric_name
        aggregation         = var.metric_alerts[alert_name].aggregation
        operator            = var.metric_alerts[alert_name].operator
        threshold           = var.metric_alerts[alert_name].threshold
        severity            = var.metric_alerts[alert_name].severity
        frequency           = var.metric_alerts[alert_name].frequency
        window_size         = var.metric_alerts[alert_name].window_size
        scoped_resource_id  = service_plan.id
        resource_group_name = "${service_plan.resource_group_name}"
        action_group_id     = strcontains(alert_name, "scaleup") ? module.action_group["scale-up"].id : strcontains(alert_name, "scaledown") ? module.action_group["scale-down"].id : null
      }
    }
  ]...)
}