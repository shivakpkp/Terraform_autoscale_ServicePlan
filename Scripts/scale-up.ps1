
# ==============================================================================
# Runbook: scale-up.ps1
# ==============================================================================
# Purpose:
#   1. Receive Azure Monitor Alert webhook
#   2. Extract the exact alertTargetIDs value
#   3. Pass the TargetResourceId to the shared scaling engine
#   4. Shared engine scales ONLY that resource
#
# Flow:
#   Azure Monitor Alert
#        |
#        v
#   Scale-Up Master
#        |
#        | TargetResourceId
#        v
#   Shared Engine
# ==============================================================================

param (
    [Parameter(Mandatory = $false)]
    [object] $WebhookData
)
$Default_Runbook_Dry_Run = $false
$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

$RESOURCE_GROUP = 'rg-autoscale-terraform'

$SHARED_ENGINE_RUNBOOK = 'shared-engine'

$MASTER_RUNBOOK_NAME = 'scaleupmaster'

# ------------------------------------------------------------------------------
# Start
# ------------------------------------------------------------------------------

Write-Output "============================================================"
Write-Output "Scale-Up Master Runbook"
Write-Output "============================================================"

Write-Output "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# ------------------------------------------------------------------------------
# Validate Webhook
# ------------------------------------------------------------------------------

if (-not $WebhookData) {
    throw "WebhookData was not received."
}

Write-Output "Webhook data received."

# ------------------------------------------------------------------------------
# Parse Alert Payload
# ------------------------------------------------------------------------------

try {
    $AlertData = $WebhookData.RequestBody | ConvertFrom-Json
}
catch {
    throw "Failed to parse Azure Monitor alert payload: $($_.Exception.Message)"
}

Write-Output "Alert payload parsed successfully."

# ------------------------------------------------------------------------------
# Get Alert Target Resource ID
# ------------------------------------------------------------------------------

$TargetResourceIds = @(
    $AlertData.data.essentials.alertTargetIDs
)

if ($TargetResourceIds.Count -eq 0) {
    throw "No alertTargetIDs were found in the alert payload."
}

# ------------------------------------------------------------------------------
# POC: Use the exact Target Resource ID from the alert
# ------------------------------------------------------------------------------

$TargetResourceId = [string]$TargetResourceIds[0]

if ([string]::IsNullOrWhiteSpace($TargetResourceId)) {
    throw "TargetResourceId is empty."
}

Write-Output ""
Write-Output "============================================================"
Write-Output "ALERT TARGET"
Write-Output "============================================================"

Write-Output "TargetResourceId:"
Write-Output $TargetResourceId

# ------------------------------------------------------------------------------
# Basic validation
# ------------------------------------------------------------------------------

if ($TargetResourceId -notmatch '^/subscriptions/.+/resourceGroups/.+/providers/.+') {
    throw "The alert TargetResourceId does not look like a valid Azure resource ID: $TargetResourceId"
}

# ------------------------------------------------------------------------------
# Authenticate
# ------------------------------------------------------------------------------

Write-Output ""
Write-Output "Authenticating using Managed Identity..."

Connect-AzAccount -Identity | Out-Null

$subscriptionId = (Get-AzContext).Subscription.Id

Write-Output "Azure Subscription: $subscriptionId"

# ------------------------------------------------------------------------------
# Find Automation Account
# ------------------------------------------------------------------------------

$automationAccounts = @(
    Get-AzAutomationAccount `
        -ResourceGroupName $RESOURCE_GROUP `
        -ErrorAction Stop
)

if ($automationAccounts.Count -eq 0) {
    throw "No Automation Account found in resource group '$RESOURCE_GROUP'."
}

$AutomationAccountName = $automationAccounts[0].AutomationAccountName

Write-Output "Automation Account: $AutomationAccountName"

# ------------------------------------------------------------------------------
# Invoke Shared Engine
# ------------------------------------------------------------------------------

Write-Output ""
Write-Output "============================================================"
Write-Output "INVOKING SHARED ENGINE"
Write-Output "============================================================"

Write-Output "Runbook      : $SHARED_ENGINE_RUNBOOK"
Write-Output "Mode         : scaleup"
Write-Output "Target ID    : $TargetResourceId"
Write-Output "Dry Run      : $Default_Runbook_Dry_Run"

$parameters = @{
    Mode                    = 'scaleup'
    TargetResourceId       = $TargetResourceId
    TargetSku              = "P1v3"
    DryRun = $Default_Runbook_Dry_Run
}

$engineJob = Start-AzAutomationRunbook `
    -ResourceGroupName $RESOURCE_GROUP `
    -AutomationAccountName $AutomationAccountName `
    -RunbookName $SHARED_ENGINE_RUNBOOK `
    -Parameters $parameters `
    -ErrorAction Stop

# ------------------------------------------------------------------------------
# Result
# ------------------------------------------------------------------------------

Write-Output ""
Write-Output "============================================================"
Write-Output "SHARED ENGINE STARTED"
Write-Output "============================================================"

Write-Output "Shared Engine Job ID: $($engineJob.JobId)"
Write-Output "Target Resource ID passed to engine:"
Write-Output $TargetResourceId

Write-Output ""
Write-Output "Scale-Up Master completed successfully."

