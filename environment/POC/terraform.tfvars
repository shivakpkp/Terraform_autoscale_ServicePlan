resource_group_name = "rg-autoscale-terraform"
location            = "canadacentral"
automation_account = {
  ll-poc-automation-account = {
    name     = "ll-poc-automation-account"
    sku_name = "Basic"
    identity = "SystemAssigned"
  }
}

automation_account_runbook = {
  rb-scale-up = {
    name        = "rb-scale-up"
    script_path = "../../Scripts/scale-up.ps1"
  }

  rb-scale-down = {
    name        = "rb-scale-down"
    script_path = "../../Scripts/scale-down.ps1"
  }

  shared-engine = {
    name        = "shared-engine"
    script_path = "../../Scripts/shared-engine.ps1"
  }
}

action_groups = {
  "scale-up" = {
    name       = "scale-up"
    short_name = "scale-up"

    runbook = [
      {
        name                  = "rb-scale-up"
        runbook_name          = "rb-scale-up"
        automation_account_id = null
        webhook_resource_id   = null
        service_uri           = null
        schema                = true
      }
    ]

    email = [
      {
        name          = "POC Notification"
        email_address = ""
      }
    ]
  }

  "scale-down" = {
    name       = "scale-down"
    short_name = "scale-down"

    runbook = [
      {
        name                  = "rb-scale-down"
        runbook_name          = "rb-scale-down"
        automation_account_id = null
        webhook_resource_id   = null
        service_uri           = null
        schema                = true
      }
    ]

    email = [
      {
        name          = "POC Notification"
        email_address = ""
      }
    ]
  }
}

Serviceplans = {
  ASP-rgautoscale-abf9 = "rg-autoscale"
  rtyui                = "rg-autoscale"
}

tags = {
  environment = "poc"
  Owner       = "ShivaKp"
  project     = "ll-autoscaling"
}