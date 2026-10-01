# Terraform Autoscale Service Plan

Automate Azure App Service Plan scaling with Terraform, Azure Monitor, and PowerShell runbooks. This project provisions Azure Automation Accounts, runbooks, action groups, and metric alerts to trigger scaling operations based on CPU and memory usage.

## How It Works

Azure Monitor evaluates App Service Plan metrics against configured thresholds. When an alert is triggered, its associated action group invokes an Azure Automation runbook to perform the scaling operation. Action groups can also send email notifications.

Terraform provisions the supporting infrastructure; the PowerShell runbooks implement the scaling logic.

## Project Structure

| Path | Description |
| --- | --- |
| `environment/POC/` | Terraform configuration for the proof-of-concept environment. |
| `modules/` | Reusable Terraform modules for provisioning Azure resources. |
| `Scripts/` | PowerShell scripts used by Azure Automation runbooks. |
| `.gitignore` | Files and directories excluded from version control. |

## Prerequisites

- Install [Terraform](https://developer.hashicorp.com/terraform/install).
- Install [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) and authenticate with `az login`.
- Select the target Azure subscription and ensure your deployment identity has permission to create the required resources and role assignments.
- Identify the target App Service Plans and their resource groups.
- Ensure the Automation Account identity has the permissions required by the runbooks to scale the target plans.

## Getting Started

### 1. Configure the Environment

Create a `terraform.tfvars` file in `environment/POC/` using the example below. Replace the resource names, email addresses, and other values with those for your environment. Keep variable names consistent with the Terraform configuration.

```hcl
location            = "canadacentral"
resource_group_name = "rg-autoscale"

automation_account = {
  poc-automation-account = {
    name     = "poc-automation-account"
    sku_name = "Basic"
    identity = "SystemAssigned"
  
}
}S

automation_account_runbook = {
  scale_up = {
    name        = "scale-up"
    script_path = "../../Scripts/scale-up.ps1"
  }
  scale_down = {
    name        = "scale-down"
    script_path = "../../Scripts/scale-down.ps1"
  }
}

action_groups = {
  scale_up = {
    name       = "scale-up-action-group"
    short_name = "ScaleUp"
    runbook = [
      {
        name                = "scale-up-runbook"
        runbook_name        = "scale-up"
        webhook_resource_id = ""
        service_uri         = ""
        schema              = true
      }
    ]
    email = [
      {
        name          = "Admin"
        email_address = "admin@example.com"
      }
    ]
  }
  scale_down = {
    name       = "scale-down-action-group"
    short_name = "ScaleDown"
    runbook = [
      {
        name                = "scale-down-runbook"
        runbook_name        = "scale-down"
        webhook_resource_id = ""
        service_uri         = ""
        schema              = true
      }
    ]
    email = [
      {
        name          = "Admin"
        email_address = "admin@example.com"
      }
    ]
  }
}

Serviceplans = {
  "service-plan-1" = "rg-autoscale"
}

metric_alerts = {
  Cpu_alert_scaleup = {
    name                = "Cpu_alert"
    resource_group_name = "rg-autoscale"
    metric_namespace    = "Microsoft.Web/serverFarms"
    metric_name         = "CpuPercentage"
    aggregation         = "Average"
    operator            = "GreaterThan"
    threshold           = 40
    severity            = 2
    frequency           = "PT1M"
    window_size         = "PT5M"
  }
  Memory_alert_scaleup = {
    name                = "Memory_alert"
    resource_group_name = "rg-autoscale"
    metric_namespace    = "Microsoft.Web/serverFarms"
    metric_name         = "MemoryPercentage"
    aggregation         = "Average"
    operator            = "GreaterThan"
    threshold           = 40
    severity            = 2
    frequency           = "PT1M"
    window_size         = "PT5M"
  }
}

tags = {
  environment = "POC"
  project     = "Autoscale"
}
```

**Configuration notes:**

- This example includes scale-up alerts only. Configure scale-down alerts and their action-group associations according to your modules and scaling requirements.
- The webhook fields are empty placeholders. Confirm whether your modules populate them automatically or require values before deployment.
- Verify that each metric alert is associated with the intended action group and target App Service Plan.

### 2. Initialize Terraform

From the repository root, run:

```bash
cd environment/POC
terraform init
```

### 3. Validate and Review the Configuration

```bash
terraform validate
terraform plan
```

Review the proposed changes before applying them.

### 4. Deploy the Resources

```bash
terraform apply
```

Review the plan and confirm the deployment when prompted.

### 5. Verify the Deployment

In the Azure portal:

- Confirm that the Automation Account, runbooks, action groups, and metric alerts were created successfully.
- Verify the runbook identity permissions and alert-to-action-group associations.
- Test the scaling behavior in a non-production environment.
- Review Automation job logs and confirm that notifications reach the configured recipients.

## Version Control

The `.gitignore` file excludes sensitive, generated, and environment-specific files, including:

| Category | Patterns |
| --- | --- |
| Local Terraform directories | `.terraform/` |
| Terraform state | `*.tfstate`, `*.tfstate.*` |
| Crash logs | `crash.log`, `crash.*.log` |
| Local variable files | `*.tfvars`, `*.tfvars.json` |
| Override files | `override.tf`, `override.tf.json`, `*_override.tf`, `*_override.tf.json` |
| State lock information | `.terraform.tfstate.lock.info` |
| Terraform CLI configuration | `.terraformrc`, `terraform.rc` |
| Saved plans | `*tfplan*`, `planout` |
| Graph output | `*.dot` |

Keep a sanitized configuration example in the README so others can configure the project without exposing environment-specific values.

## Cleanup

From `environment/POC/`, run:

```bash
terraform destroy
```

Review the destruction plan before confirming. This removes the resources managed by this Terraform configuration.

## Notes

- Customize alert thresholds and scaling behavior for your workload.
- Do not hardcode credentials, client secrets, or webhook URLs in committed files. Use environment variables or an appropriate secret management solution.
- Review the PowerShell scripts and Terraform modules before using this proof of concept in production.

## License

This project is licensed under the MIT License. Include a `LICENSE` file in the repository containing the MIT license text.
