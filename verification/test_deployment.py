"""Read-only checks against real deployed Azure resources. No scaling calls."""
import json
from datetime import timedelta
from pathlib import Path

import pytest

# Read expected values from a file beside this Python file.
CONFIG = json.loads(Path(__file__).with_name("expected.json").read_text())
RG = CONFIG["resource_group"]
ACCOUNT = CONFIG["automation_account"]


def resource_id(subscription, resource_group, provider, name):
    return (
        f"/subscriptions/{subscription}/resourceGroups/{resource_group}"
        f"/providers/{provider}/{name}"
    )


def test_automation_identity(automation):
    account = automation.automation_account.get(RG, ACCOUNT)
    assert account.identity is not None, "Automation Account has no identity"
    assert "SystemAssigned" in account.identity.type, "System-assigned identity is disabled"
    assert account.identity.principal_id, "Managed Identity principal ID is missing"


# pytest runs this function once for each runbook name.
@pytest.mark.parametrize("name", CONFIG["runbooks"])
def test_runbook_is_published(automation, name):
    runbook = automation.runbook.get(RG, ACCOUNT, name)
    assert runbook.properties is not None, f"Runbook {name} has no properties"
    assert runbook.properties.state == "Published", f"Runbook {name} is not published"


# Two plans x four alert definitions = eight independent test cases.
ALERT_CASES = [
    (plan, plan_rg, rule)
    for plan, plan_rg in CONFIG["plans"].items()
    for rule in CONFIG["alerts"]
]


@pytest.mark.parametrize(
    "plan,plan_rg,rule",
    ALERT_CASES,
    ids=[f"{plan}-{rule['suffix']}" for plan, _, rule in ALERT_CASES],
)
def test_metric_alert(monitor, subscription_id, plan, plan_rg, rule):
    name = f"{plan}-{rule['suffix']}"
    alert = monitor.metric_alerts.get(RG, name)

    expected_plan = resource_id(
        subscription_id, plan_rg, "Microsoft.Web/serverfarms", plan
    )
    expected_group = resource_id(
        subscription_id, RG, "Microsoft.Insights/actionGroups", rule["group"]
    )

    assert alert.enabled is True, f"Alert {name} is disabled"
    # Azure IDs are compared without regard to letter case.
    assert {item.lower() for item in alert.scopes or []} == {expected_plan.lower()}, "Wrong alert scope"
    assert alert.evaluation_frequency == timedelta(minutes=1), "Wrong evaluation frequency"
    assert alert.window_size == timedelta(minutes=5), "Wrong evaluation window"

    criteria = getattr(alert.criteria, "all_of", None) or []
    assert len(criteria) == 1, "Expected one metric condition"
    condition = criteria[0]
    assert condition.metric_name == rule["metric"], "Wrong metric"
    assert condition.metric_namespace.lower() == "microsoft.web/serverfarms", "Wrong metric namespace"
    assert condition.operator == rule["operator"], "Wrong comparison operator"
    assert condition.threshold == rule["threshold"], "Wrong threshold"
    assert condition.time_aggregation == "Average", "Wrong aggregation"

    actual_groups = {action.action_group_id.lower() for action in alert.actions or []}
    assert actual_groups == {expected_group.lower()}, "Alert routes to the wrong Action Group"


@pytest.mark.parametrize("group_name,runbook_name", CONFIG["routes"].items())
def test_action_group_routing(monitor, subscription_id, group_name, runbook_name):
    group = monitor.action_groups.get(RG, group_name)
    assert group.enabled is True, f"Action Group {group_name} is disabled"

    receivers = group.automation_runbook_receivers or []
    assert len(receivers) == 1, "Expected one Automation runbook receiver"
    receiver = receivers[0]
    expected_account = resource_id(
        subscription_id, RG, "Microsoft.Automation/automationAccounts", ACCOUNT
    )
    expected_webhook = f"{expected_account}/webhooks/{runbook_name}-webhook"

    assert receiver.runbook_name == runbook_name, "Wrong receiver runbook"
    assert receiver.automation_account_id.lower() == expected_account.lower(), "Wrong Automation Account"
    assert receiver.webhook_resource_id.lower() == expected_webhook.lower(), "Wrong webhook reference"
    assert receiver.use_common_alert_schema is True, "Common alert schema is disabled"
    # Never print the receiver or its service_uri: the URI can contain a secret.
