# Scales exactly one enrolled App Service Plan. Called by the master runbooks.
# Approved policy: B1 -> P1v3 (up), P1v3 -> B1 (down).
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $TargetResourceId,

    [Parameter(Mandatory = $true)]
    [ValidateSet('B1', 'P1v3')]
    [string] $TargetSku,

    [Parameter(Mandatory = $true)]
    [ValidateSet('scaleup', 'scaledown')]
    [string] $Mode,

    [ValidateRange(1, 100)]
    [double] $CpuLowThreshold = 20,
    [ValidateRange(1, 100)]
    [double] $MemoryLowThreshold = 20,
    [ValidateRange(5, 30)]
    [int] $MetricWindowMinutes = 5,
    [ValidateRange(60, 3600)]
    [int] $CompletionTimeoutSeconds = 1200
)

$ErrorActionPreference = 'Stop'
$currentSku = ''
$currentCapacity = 0
$apiVersion = '2025-05-01'

function Write-ScalingResult {
    param ([string] $Result, [string] $Message, [bool] $Succeeded = $true)
    # This helper writes output; each caller must explicitly return or throw.
    [ordered]@{
        SchemaVersion    = 1
        Succeeded        = $Succeeded
        Result           = $Result
        Message          = $Message
        TargetResourceId = $TargetResourceId
        Mode             = $Mode
        CurrentSku       = $currentSku
        TargetSku        = $TargetSku
        WorkerCount      = $currentCapacity
    } | ConvertTo-Json -Compress
}

function Get-Plan {
    $response = Invoke-AzRestMethod -Method GET -Path $planPath -DefaultProfile $context
    if ($response.StatusCode -ne 200) {
        throw "Reading the App Service Plan failed (HTTP $($response.StatusCode))."
    }
    return ($response.Content | ConvertFrom-Json)
}

function Get-ScaleDownDecision {
    # Allow two minutes for metric ingestion. Inspect five complete minute buckets.
    # Every minute average must be below its threshold: stricter than a single
    # five-minute average, which could conceal a recent spike.
    $utcNow = [DateTime]::UtcNow
    $windowEnd = $utcNow.AddTicks(-($utcNow.Ticks % [TimeSpan]::TicksPerMinute)).AddMinutes(-2)
    $windowStart = $windowEnd.AddMinutes(-$MetricWindowMinutes)
    $timespan = [Uri]::EscapeDataString("$($windowStart.ToString('o'))/$($windowEnd.ToString('o'))")
    $metricPath = "$TargetResourceId/providers/Microsoft.Insights/metrics" +
        "?api-version=2023-10-01&metricnamespace=Microsoft.Web%2Fserverfarms" +
        "&metricnames=CpuPercentage,MemoryPercentage&aggregation=Average" +
        "&interval=PT1M&timespan=$timespan"
    $response = Invoke-AzRestMethod -Method GET -Path $metricPath -DefaultProfile $context
    if ($response.StatusCode -ne 200) {
        throw "Reading scale-down metrics failed (HTTP $($response.StatusCode)); no update submitted."
    }
    $metrics = ($response.Content | ConvertFrom-Json).value
    $limits = @{ CpuPercentage = $CpuLowThreshold; MemoryPercentage = $MemoryLowThreshold }
    foreach ($name in @('CpuPercentage', 'MemoryPercentage')) {
        $metric = @($metrics | Where-Object { $_.name.value -eq $name })
        if ($metric.Count -ne 1 -or $metric[0].errorCode -notin @($null, '', 'Success')) {
            return @{ Allowed = $false; Reason = "Missing or invalid $name metrics." }
        }
        $series = @($metric[0].timeseries)
        # Request an aggregate series without a dimension filter. Never silently
        # choose one worker when an unexpected set of series is returned.
        if ($series.Count -ne 1) {
            return @{ Allowed = $false; Reason = "Expected one aggregate $name time series." }
        }
        for ($i = 0; $i -lt $MetricWindowMinutes; $i++) {
            $timestamp = $windowStart.AddMinutes($i)
            $points = @($series[0].data | Where-Object {
                $null -ne $_.timeStamp -and ([DateTimeOffset]$_.timeStamp).UtcDateTime -eq $timestamp
            })
            if ($points.Count -ne 1 -or $null -eq $points[0].average) {
                return @{ Allowed = $false; Reason = "Incomplete $name metric window; scaling skipped." }
            }
            $value = [double]$points[0].average
            if ([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0 -or $value -gt 100) {
                return @{ Allowed = $false; Reason = "Invalid $name metric value." }
            }
            if ($value -ge $limits[$name]) {
                return @{ Allowed = $false; Reason = "$name is not below $($limits[$name])% for every minute." }
            }
        }
    }
    return @{ Allowed = $true; Reason = 'Both CPU and memory are below their thresholds.' }
}

try {
    if ($TargetResourceId -notmatch '^/subscriptions/([0-9a-f-]{36})/resourceGroups/([^/]+)/providers/Microsoft\.Web/serverfarms/([^/]+)$') {
        throw 'TargetResourceId must identify exactly one Microsoft.Web/serverfarms resource.'
    }
    $subscriptionId = $Matches[1]
    $expectedSource = if ($Mode -eq 'scaleup') { 'B1' } else { 'P1v3' }
    $expectedTarget = if ($Mode -eq 'scaleup') { 'P1v3' } else { 'B1' }
    if ($TargetSku -ne $expectedTarget) {
        throw "Policy permits only $expectedSource -> $expectedTarget for $Mode."
    }

    Disable-AzContextAutosave -Scope Process | Out-Null
    $context = (Connect-AzAccount -Identity).Context
    $context = Set-AzContext -SubscriptionId $subscriptionId -DefaultProfile $context
    $planPath = "${TargetResourceId}?api-version=$apiVersion"
    $plan = Get-Plan
    if ($plan.type -ne 'Microsoft.Web/serverfarms') {
        throw 'Target is not an App Service Plan.'
    }
    $currentSku = [string]$plan.sku.name
    $currentCapacity = [int]$plan.sku.capacity
    $enrollmentTag = if ($Mode -eq 'scaleup') { 'AutoScaleUp' } else { 'AutoScaleDown' }
    if ([string]$plan.tags.$enrollmentTag -ine 'true') {
        Write-ScalingResult -Result 'NotEnrolled' -Message "Required tag $enrollmentTag=true is absent."
        return
    }
    if ($plan.properties.provisioningState -ne 'Succeeded' -or $plan.properties.status -ne 'Ready') {
        Write-ScalingResult -Result 'Busy' -Message 'Plan is not in Succeeded/Ready state; no update submitted.'
        return
    }
    if ($currentSku -eq $TargetSku) {
        Write-ScalingResult -Result 'NoOp' -Message "Plan already uses $TargetSku."
        return
    }
    if ($currentSku -ne $expectedSource) {
        Write-ScalingResult -Result 'PolicySkipped' -Message "SKU $currentSku is outside the approved $expectedSource -> $expectedTarget transition."
        return
    }
    if ($currentCapacity -lt 1) {
        throw 'Cannot determine a valid worker count; refusing to guess.'
    }

    $skuResponse = Invoke-AzRestMethod -Method GET -Path "$TargetResourceId/skus?api-version=$apiVersion" -DefaultProfile $context
    if ($skuResponse.StatusCode -ne 200) { throw 'Unable to retrieve permitted SKUs.' }
    $available = @(($skuResponse.Content | ConvertFrom-Json).value | Where-Object { $_.sku.name -eq $TargetSku })
    if ($available.Count -eq 0) { throw "Azure does not list $TargetSku as available for this plan." }
    # Azure also validates tier features and capacity when processing the request.
    if ($Mode -eq 'scaledown' -and $currentCapacity -gt 3) {
        throw 'B1 supports at most three workers; preserving this worker count is not possible.'
    }
    if ($Mode -eq 'scaledown') {
        $decision = Get-ScaleDownDecision
        if (-not $decision.Allowed) {
            Write-ScalingResult -Result 'MetricsSkipped' -Message $decision.Reason
            return
        }
    }

    # Re-read immediately before submitting, so changes observed during validation
    # cannot be overwritten. This is a guard, not a distributed lock.
    $latest = Get-Plan
    if ($latest.sku.name -ne $currentSku -or [int]$latest.sku.capacity -ne $currentCapacity -or
        [string]$latest.tags.$enrollmentTag -ine 'true' -or
        $latest.properties.provisioningState -ne 'Succeeded' -or $latest.properties.status -ne 'Ready') {
        Write-ScalingResult -Result 'ConcurrentChange' -Message 'Plan changed during validation; no update submitted.'
        return
    }
    # PATCH modifies only the SKU, preserving unrelated resource properties.
    $payload = @{ sku = @{ name = $TargetSku; capacity = $currentCapacity } } | ConvertTo-Json -Depth 5
    $response = Invoke-AzRestMethod -Method PATCH -Path $planPath -Payload $payload -DefaultProfile $context
    if ($response.StatusCode -notin @(200, 201, 202)) {
        throw "SKU update rejected (HTTP $($response.StatusCode))."
    }

    # An accepted request is not completion. Confirm observable resource state.
    $deadline = [DateTime]::UtcNow.AddSeconds($CompletionTimeoutSeconds)
    do {
        Start-Sleep -Seconds 15
        $actual = Get-Plan
        if ($actual.properties.provisioningState -in @('Failed', 'Canceled', 'Cancelled')) {
            throw "Azure scaling ended in state $($actual.properties.provisioningState)."
        }
        if ($actual.sku.name -eq $TargetSku -and
            [int]$actual.sku.capacity -eq $currentCapacity -and
            [int]$actual.properties.numberOfWorkers -eq $currentCapacity -and
            $actual.properties.provisioningState -eq 'Succeeded' -and
            $actual.properties.status -eq 'Ready') {
            Write-ScalingResult -Result 'Changed' -Message "Verified $currentSku -> $TargetSku with $currentCapacity worker(s)."
            return
        }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Timed out waiting for the target SKU and ready workers. Azure may still be processing the update; inspect the plan before retrying.'
}
catch {
    Write-ScalingResult -Result 'Failed' -Message $_.Exception.Message -Succeeded $false
    throw
}
