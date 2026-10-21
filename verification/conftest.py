"""Shared pytest setup. Fixtures are created when a test requests them."""
import os

import pytest
from azure.identity import EnvironmentCredential
from azure.mgmt.automation import AutomationClient
from azure.mgmt.monitor import MonitorManagementClient


@pytest.fixture(scope="session")
def subscription_id():
    required = (
        "AZURE_CLIENT_ID", "AZURE_CLIENT_SECRET",
        "AZURE_TENANT_ID", "AZURE_SUBSCRIPTION_ID",
    )
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        pytest.fail("Missing environment variables: " + ", ".join(missing))
    return os.environ["AZURE_SUBSCRIPTION_ID"]


@pytest.fixture(scope="session")
def credential(subscription_id):
    # The subscription fixture validates environment variables first.
    with EnvironmentCredential() as identity:
        yield identity


@pytest.fixture(scope="session")
def automation(credential, subscription_id):
    with AutomationClient(credential, subscription_id) as client:
        yield client


@pytest.fixture(scope="session")
def monitor(credential, subscription_id):
    with MonitorManagementClient(credential, subscription_id) as client:
        yield client
