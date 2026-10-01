# =============================================================================
# Module: metric_alert
# =============================================================================
# Description: Provisions an Azure Monitor metric alert (single criterion) scoped
#              to one resource. Used for CPU %, CpuTime Total, BytesReceived /
#              BytesSent (portal Data In / Data Out on the plan), etc.
#
# Window: PT5M by default — aggregates over five minutes (Average or Total per metric).
# Frequency: PT1M — condition is checked every minute.
# =============================================================================

resource "azurerm_monitor_metric_alert" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  scopes              = [var.scoped_resource_id]
  description         = "Fires when ${var.metric_name} exceeds ${var.threshold} (${var.aggregation} over ${var.window_size}). Triggers scale-up runbook via Action Group."
  severity            = var.severity

  # How often the condition is evaluated
  frequency = var.frequency

  # Time window over which the aggregation is computed
  window_size = var.window_size

  criteria {
    metric_namespace = var.metric_namespace
    metric_name      = var.metric_name
    aggregation      = var.aggregation
    operator         = var.operator
    threshold        = var.threshold
  }

  # Fire the Action Group when the alert is triggered;
  # Action Group sends email + invokes the scale-up runbook
  action {
    action_group_id = var.action_group_id
  }

  tags = var.tags
}
