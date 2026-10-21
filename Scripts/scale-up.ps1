# Receives an Azure Monitor common-schema alert and waits for the shared engine.
param (
    [object] $WebhookData,
    [string] $AutomationResourceGroup = 'rg-autoscale-terraform',
    [string] $AutomationAccountName = 'poc-automation-account',
    [string] $SharedEngineRunbookName = 'shared-engine',
    # Leave empty when the Automation Account and target are in one subscription.
    [string] $AutomationSubscriptionId = '',
    [ValidateRange(1800, 7200)]
    [int] $JobTimeoutSeconds = 2400
)

$ErrorActionPreference = 'Stop'
$mode = 'scaleup'
$targetSku = 'P1v3'

if ($WebhookData -is [string]) {
    $WebhookData = $WebhookData | ConvertFrom-Json
}
if ($null -eq $WebhookData -or [string]::IsNullOrWhiteSpace([string]$WebhookData.RequestBody)) {
    throw 'WebhookData.RequestBody is required.'
}
$alert = $WebhookData.RequestBody | ConvertFrom-Json
if ($alert.schemaId -ne 'azureMonitorCommonAlertSchema') {
    throw 'Expected the Azure Monitor common alert schema.'
}
$essentials = $alert.data.essentials
if ($essentials.monitorCondition -eq 'Resolved') {
    [ordered]@{ Succeeded = $true; Result = 'Ignored'; Message = 'Resolved alert ignored.' } | ConvertTo-Json -Compress
    return
}
if ($essentials.monitorCondition -ne 'Fired') {
    throw 'Only Fired or Resolved monitorCondition values are accepted.'
}
if ($essentials.signalType -ne 'Metric') {
    throw 'Only metric alerts are accepted.'
}
$targets = @($essentials.alertTargetIDs)
if ($targets.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$targets[0])) {
    throw 'Expected exactly one alertTargetIDs entry; no resource was selected.'
}
$targetResourceId = [string]$targets[0]
if ($targetResourceId -notmatch '^/subscriptions/([0-9a-f-]{36})/resourceGroups/([^/]+)/providers/Microsoft\.Web/serverfarms/([^/]+)$') {
    throw 'Alert target must be an App Service Plan resource ID.'
}
$targetSubscriptionId = $Matches[1]

Disable-AzContextAutosave -Scope Process | Out-Null
$context = (Connect-AzAccount -Identity).Context
if ([string]::IsNullOrWhiteSpace($AutomationSubscriptionId)) {
    $AutomationSubscriptionId = $targetSubscriptionId
}
$context = Set-AzContext -SubscriptionId $AutomationSubscriptionId -DefaultProfile $context
$jobArguments = @{
    ResourceGroupName     = $AutomationResourceGroup
    AutomationAccountName = $AutomationAccountName
    DefaultProfile        = $context
}
# Use the explicitly configured Automation Account, never the first search result.
$parameters = @{
    Mode                     = $mode
    TargetResourceId         = $targetResourceId
    TargetSku                = $targetSku
    CompletionTimeoutSeconds = 1200
}
$job = Start-AzAutomationRunbook @jobArguments -RunbookName $SharedEngineRunbookName -Parameters $parameters
if ($null -eq $job.JobId) { throw 'Azure did not return a child job ID.' }
Write-Verbose "Shared engine job: $($job.JobId)"

$deadline = [DateTime]::UtcNow.AddSeconds($JobTimeoutSeconds)
do {
    $status = Get-AzAutomationJob @jobArguments -Id $job.JobId
    if ($status.Status -eq 'Completed') { break }
    if ($status.Status -in @('Failed', 'Stopped', 'Suspended', 'Disconnected', 'Blocked')) {
        throw "Shared engine job $($job.JobId) ended in state $($status.Status). Inspect its error stream."
    }
    if ([DateTime]::UtcNow -ge $deadline) {
        # A parent timeout does not cancel the child or roll back an ARM update.
        throw "Timed out waiting for shared engine job $($job.JobId). It may still be running; inspect it before retrying."
    }
    Start-Sleep -Seconds 15
} while ($true)

# Output records may appear shortly after Completed. Fetch the full record value;
# the Summary field can be truncated and must not be used to parse JSON.
$result = $null
$outputDeadline = [DateTime]::UtcNow.AddSeconds(90)
do {
    $records = @(Get-AzAutomationJobOutput @jobArguments -Id $job.JobId -Stream Output)
    foreach ($record in $records) {
        $fullRecord = Get-AzAutomationJobOutputRecord @jobArguments -JobId $job.JobId -Id $record.StreamRecordId
        try { $candidate = ([string]$fullRecord.Value) | ConvertFrom-Json -ErrorAction Stop }
        catch { continue }
        if ($candidate.SchemaVersion -eq 1 -and
            $candidate.TargetResourceId -eq $targetResourceId -and
            $candidate.Mode -eq $mode -and $candidate.TargetSku -eq $targetSku) {
            $result = $candidate
        }
    }
    if ($null -ne $result) { break }
    Start-Sleep -Seconds 10
} while ([DateTime]::UtcNow -lt $outputDeadline)

if ($null -eq $result) {
    throw "Job $($job.JobId) completed without a readable scaling result; outcome is unverified."
}
if ($result.Succeeded -ne $true -or $result.Result -eq 'Failed') {
    throw "Shared engine job $($job.JobId) reported failure: $($result.Message)"
}
$knownResults = @('Changed', 'NoOp', 'NotEnrolled', 'Busy', 'PolicySkipped', 'MetricsSkipped', 'ConcurrentChange')
if ($result.Result -notin $knownResults) { throw "Unexpected engine result: $($result.Result)" }
# Preserve the engine's verified outcome. Completed does not necessarily mean Changed.
$result | Add-Member -NotePropertyName EngineJobId -NotePropertyValue ([string]$job.JobId) -Force
$result | ConvertTo-Json -Depth 5 -Compress
