# Azure runbook name: rb-scale-down
# Calls shared-engine and verifies its result.

param (
    [object] $WebhookData,

    [string] $AutomationResourceGroup = 'rg-autoscale-terraform',

    [string] $AutomationAccountName = 'poc-automation-account',

    [string] $SharedEngineRunbookName = 'shared-engine',

    # Leave empty when the Automation Account and target plan
    # are in the same subscription.
    [string] $AutomationSubscriptionId = '',

    [ValidateRange(1800, 7200)]
    [int] $JobTimeoutSeconds = 2400
)

$ErrorActionPreference = 'Stop'

$mode = 'scaledown'
$targetSku = 'B1'
$stage = 'Starting runbook'

function Write-Log {
    param ([string] $Message)

    $timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')
    Write-Output "[$timestamp UTC] $Message"
}

try {
    # 1. Read webhook
    $stage = 'Reading webhook'
    Write-Log 'STEP 1: Reading webhook.'

    if ($WebhookData -is [string]) {
        $WebhookData = $WebhookData | ConvertFrom-Json
    }

    if (
        $null -eq $WebhookData -or
        [string]::IsNullOrWhiteSpace([string]$WebhookData.RequestBody)
    ) {
        throw 'WebhookData.RequestBody is missing.'
    }

    $alert = $WebhookData.RequestBody | ConvertFrom-Json

    if ($alert.schemaId -ne 'azureMonitorCommonAlertSchema') {
        throw 'Expected the Azure Monitor common alert schema.'
    }

    $essentials = $alert.data.essentials

    Write-Log "Alert rule: $($essentials.alertRule)"
    Write-Log "Alert condition: $($essentials.monitorCondition)"

    # 2. Ignore resolved notifications
    $stage = 'Checking alert condition'

    if ($essentials.monitorCondition -eq 'Resolved') {
        Write-Log 'Resolved notification ignored. No scaling requested.'

        [ordered]@{
            Succeeded = $true
            Result    = 'Ignored'
            Message   = 'Resolved alert ignored.'
        } | ConvertTo-Json -Compress

        return
    }

    if ($essentials.monitorCondition -ne 'Fired') {
        throw "Unexpected monitorCondition: '$($essentials.monitorCondition)'."
    }

    if ($essentials.signalType -ne 'Metric') {
        throw 'Only metric alerts are accepted.'
    }

    # 3. Validate target
    $stage = 'Validating alert target'
    Write-Log 'STEP 2: Validating the target App Service Plan.'

    $targets = @($essentials.alertTargetIDs)

    if (
        $targets.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$targets[0])
    ) {
        throw 'Expected exactly one resource in alertTargetIDs.'
    }

    $targetResourceId = [string]$targets[0]

    $resourcePattern = '^/subscriptions/([0-9a-f-]{36})/resourceGroups/([^/]+)/providers/Microsoft\.Web/serverfarms/([^/]+)$'

    if ($targetResourceId -notmatch $resourcePattern) {
        throw 'The target is not a valid App Service Plan resource ID.'
    }

    $targetSubscriptionId = $Matches[1]

    Write-Log "Target resource: $targetResourceId"
    Write-Log "Target SKU: $targetSku"

    # 4. Authenticate
    $stage = 'Disabling Azure context autosave'
    Write-Log 'STEP 3: Disabling Azure context autosave.'

    Disable-AzContextAutosave `
        -Scope Process `
        -ErrorAction Stop | Out-Null

    $stage = 'Authenticating with Managed Identity'
    Write-Log 'STEP 4: Signing in with Managed Identity.'

    $login = Connect-AzAccount -Identity -ErrorAction Stop
    $context = $login.Context

    if ($null -eq $context) {
        throw 'Managed Identity sign-in returned no Azure context.'
    }

    Write-Log 'Managed Identity sign-in succeeded.'

    # 5. Select subscription
    $stage = 'Selecting Azure subscription'

    if ([string]::IsNullOrWhiteSpace($AutomationSubscriptionId)) {
        $AutomationSubscriptionId = $targetSubscriptionId
    }

    Write-Log "STEP 5: Selecting subscription $AutomationSubscriptionId."

    $context = Set-AzContext `
        -SubscriptionId $AutomationSubscriptionId `
        -DefaultProfile $context `
        -ErrorAction Stop

    Write-Log 'Subscription selected successfully.'

    # 6. Start shared-engine
    $jobArguments = @{
        ResourceGroupName     = $AutomationResourceGroup
        AutomationAccountName = $AutomationAccountName
        DefaultProfile        = $context
        ErrorAction           = 'Stop'
    }

    $engineParameters = @{
        Mode                     = $mode
        TargetResourceId         = $targetResourceId
        TargetSku                = $targetSku
        CompletionTimeoutSeconds = 1200
    }

    $stage = 'Starting shared-engine'

    Write-Log 'STEP 6: Starting shared-engine.'
    Write-Log "Resource group: $AutomationResourceGroup"
    Write-Log "Automation Account: $AutomationAccountName"
    Write-Log "Runbook name: $SharedEngineRunbookName"

    $job = Start-AzAutomationRunbook @jobArguments `
        -RunbookName $SharedEngineRunbookName `
        -Parameters $engineParameters

    if ($null -eq $job.JobId) {
        throw 'Azure did not return a shared-engine job ID.'
    }

    Write-Log "Shared engine started. Job ID: $($job.JobId)"

    # 7. Wait for completion
    $stage = 'Waiting for shared-engine'
    Write-Log 'STEP 7: Waiting for shared-engine to finish.'

    $deadline = [DateTime]::UtcNow.AddSeconds($JobTimeoutSeconds)
    $previousStatus = ''

    while ($true) {
        $engineJob = Get-AzAutomationJob @jobArguments -Id $job.JobId
        $currentStatus = [string]$engineJob.Status

        if ($currentStatus -ne $previousStatus) {
            Write-Log "Shared engine status: $currentStatus"
            $previousStatus = $currentStatus
        }

        if ($currentStatus -eq 'Completed') {
            break
        }

        if (
            $currentStatus -in @(
                'Failed',
                'Stopped',
                'Suspended',
                'Disconnected',
                'Blocked'
            )
        ) {
            throw (
                "Shared engine job $($job.JobId) ended with status " +
                "'$currentStatus'. Inspect that job's error stream."
            )
        }

        if ([DateTime]::UtcNow -ge $deadline) {
            throw (
                "Timed out waiting for job $($job.JobId). " +
                'The child may still be running; inspect it before retrying.'
            )
        }

        Start-Sleep -Seconds 15
    }

    # 8. Read the full output records
    $stage = 'Reading shared-engine output'
    Write-Log 'STEP 8: Reading the shared engine result.'

    $result = $null
    $outputDeadline = [DateTime]::UtcNow.AddSeconds(90)

    do {
        $records = @(
            Get-AzAutomationJobOutput @jobArguments `
                -Id $job.JobId `
                -Stream Output
        )

        foreach ($record in $records) {
            $fullRecord = Get-AzAutomationJobOutputRecord @jobArguments `
                -JobId $job.JobId `
                -Id $record.StreamRecordId

            # Azure returns the JSON inside Value.value.
            # Also support a direct string value.
            if ($fullRecord.Value -is [string]) {
                $jsonText = $fullRecord.Value
            }
            else {
                $jsonText = $fullRecord.Value.value
            }

            if (
                $jsonText -isnot [string] -or
                [string]::IsNullOrWhiteSpace($jsonText)
            ) {
                continue
            }

            try {
                $candidate = $jsonText |
                    ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                # Ordinary text output is not a scaling result.
                continue
            }

            if (
                $candidate.SchemaVersion -eq 1 -and
                $candidate.TargetResourceId -eq $targetResourceId -and
                $candidate.Mode -eq $mode -and
                $candidate.TargetSku -eq $targetSku
            ) {
                $result = $candidate
            }
        }

        if ($null -ne $result) {
            break
        }

        Start-Sleep -Seconds 10

    } while ([DateTime]::UtcNow -lt $outputDeadline)

    if ($null -eq $result) {
        throw (
            "Job $($job.JobId) completed without a matching readable result. " +
            'The scaling outcome is unverified; inspect the child job output.'
        )
    }

    # 9. Validate and report the engine's outcome
    $stage = 'Validating shared-engine result'

    if ($result.Succeeded -ne $true -or $result.Result -eq 'Failed') {
        throw "Shared engine reported failure: $($result.Message)"
    }

    $knownResults = @(
        'Changed',
        'NoOp',
        'NotEnrolled',
        'Busy',
        'PolicySkipped',
        'MetricsSkipped',
        'ConcurrentChange'
    )

    if ($result.Result -notin $knownResults) {
        throw "Unexpected shared engine result: $($result.Result)"
    }

    Write-Log "Result: $($result.Result)"
    Write-Log "Details: $($result.Message)"

    $result | Add-Member `
        -NotePropertyName EngineJobId `
        -NotePropertyValue ([string]$job.JobId) `
        -Force

    $result | ConvertTo-Json -Depth 5 -Compress

    Write-Log 'Scale-down caller completed.'
}
catch {
    $failure = $_

    Write-Log "FAILED AT: $stage"
    Write-Log "ERROR: $($failure.Exception.Message)"
    Write-Log "ERROR ID: $($failure.FullyQualifiedErrorId)"
    Write-Log "LOCATION: $($failure.InvocationInfo.PositionMessage)"
    Write-Log "STACK: $($failure.ScriptStackTrace)"

    throw
}