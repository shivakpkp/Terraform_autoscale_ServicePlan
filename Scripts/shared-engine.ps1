# ==============================================================================
# Runbook: shared-engine.ps1
# Purpose : Scale ONE App Service Plan identified by TargetResourceId
# Called  : Scale-Up Master / Scale-Down Master
# ==============================================================================

param (
    [Parameter(Mandatory = $true)]
    [string] $TargetResourceId,

    [Parameter(Mandatory = $true)]
    [string] $TargetSku,

    [Parameter(Mandatory = $true)]
    [ValidateSet('scaleup', 'scaledown')]
    [string] $Mode,

    [Parameter(Mandatory = $false)]
    [bool] $DryRun = $true
)

$ErrorActionPreference = 'Stop'

# ==============================================================================
# Helper: Return result
# ==============================================================================

function Return-Result {
    param (
        [bool]   $Succeeded,
        [string] $Result,
        [string] $Message,
        [string] $CurrentSku = '',
        [string] $TargetSku = ''
    )

    $resultObject = [ordered]@{
        Succeeded       = $Succeeded
        Result          = $Result
        Message         = $Message
        TargetResourceId = $TargetResourceId
        Mode             = $Mode
        CurrentSku      = $CurrentSku
        TargetSku       = $TargetSku
        DryRun          = $DryRun
    }

    $resultObject | ConvertTo-Json -Compress

    if (-not $Succeeded) {
        throw $Message
    }
}

# ==============================================================================
# 1. Validate input
# ==============================================================================

if ([string]::IsNullOrWhiteSpace($TargetResourceId)) {
    Return-Result `
        -Succeeded $false `
        -Result 'InvalidInput' `
        -Message 'TargetResourceId is empty.'
}

if ([string]::IsNullOrWhiteSpace($TargetSku)) {
    Return-Result `
        -Succeeded $false `
        -Result 'InvalidInput' `
        -Message 'TargetSku is empty.'
}

Write-Output "================================================="
Write-Output "Shared App Service Plan Scaling Engine"
Write-Output "Mode              : $Mode"
Write-Output "Target Resource ID: $TargetResourceId"
Write-Output "Target SKU        : $TargetSku"
Write-Output "Dry Run           : $DryRun"
Write-Output "================================================="

# ==============================================================================
# 2. Authenticate
# ==============================================================================

Write-Output "Authenticating using Managed Identity..."

Connect-AzAccount -Identity | Out-Null

# ==============================================================================
# 3. Get the target App Service Plan
# ==============================================================================

Write-Output "Getting target App Service Plan..."

$plan = Get-AzResource `
    -ResourceId $TargetResourceId `
    -ExpandProperties

if ($null -eq $plan) {
    Return-Result `
        -Succeeded $false `
        -Result 'NotFound' `
        -Message "App Service Plan was not found: $TargetResourceId"
}

if ($plan.ResourceType -ne 'Microsoft.Web/serverfarms') {
    Return-Result `
        -Succeeded $false `
        -Result 'InvalidResourceType' `
        -Message "Target resource is not an App Service Plan. Resource type: $($plan.ResourceType)"
}

$planName = $plan.Name
$resourceGroup = $plan.ResourceGroupName
$location = $plan.Location

Write-Output "Plan Name       : $planName"
Write-Output "Resource Group  : $resourceGroup"
Write-Output "Location        : $location"

# ==============================================================================
# 4. Get current App Service Plan
# ==============================================================================

$planDetails = Get-AzAppServicePlan `
    -ResourceGroupName $resourceGroup `
    -Name $planName

if ($null -eq $planDetails) {
    Return-Result `
        -Succeeded $false `
        -Result 'NotFound' `
        -Message "Unable to retrieve App Service Plan '$planName'."
}

$currentSku = $planDetails.Sku.Name
$currentCapacity = $planDetails.Sku.Capacity

Write-Output "Current SKU     : $currentSku"
Write-Output "Target SKU      : $TargetSku"
Write-Output "Current Workers : $currentCapacity"

# ==============================================================================
# 5. Check enrollment tags
# ==============================================================================

$tags = if ($null -ne $planDetails.Tags) {
    $planDetails.Tags
}
else {
    @{}
}

$scaleUpEnabled = $tags['AutoScaleUp']
$scaleDownEnabled = $tags['AutoScaleDown']

if ($Mode -eq 'scaleup') {

    if ([string]$scaleUpEnabled -notmatch '^(?i)true$') {
        Return-Result `
            -Succeeded $false `
            -Result 'NotEnrolled' `
            -Message "App Service Plan '$planName' is not enrolled for scale-up." `
            -CurrentSku $currentSku `
            -TargetSku $TargetSku
    }
}

if ($Mode -eq 'scaledown') {

    if ([string]$scaleDownEnabled -notmatch '^(?i)true$') {
        Return-Result `
            -Succeeded $false `
            -Result 'NotEnrolled' `
            -Message "App Service Plan '$planName' is not enrolled for scale-down." `
            -CurrentSku $currentSku `
            -TargetSku $TargetSku
    }
}

# ==============================================================================
# 6. Validate target SKU
# ==============================================================================

Write-Output "Validating target SKU..."

$subscriptionId = (Get-AzContext).Subscription.Id

$skuUri = "/subscriptions/$subscriptionId" +
          "/resourceGroups/$resourceGroup" +
          "/providers/Microsoft.Web/serverfarms/$planName" +
          "/skus?api-version=2022-03-01"

$skuResponse = Invoke-AzRestMethod `
    -Method GET `
    -Path $skuUri

if ($skuResponse.StatusCode -ne 200) {
    Return-Result `
        -Succeeded $false `
        -Result 'SkuValidationFailed' `
        -Message "Unable to retrieve valid SKUs for '$planName'." `
        -CurrentSku $currentSku `
        -TargetSku $TargetSku
}

$validSkus = @(
    ($skuResponse.Content | ConvertFrom-Json).value |
    ForEach-Object {
        $_.sku.name
    }
)

if ($TargetSku -notin $validSkus) {

    Return-Result `
        -Succeeded $false `
        -Result 'InvalidSku' `
        -Message "SKU '$TargetSku' is not valid for App Service Plan '$planName'. Valid SKUs: $($validSkus -join ', ')" `
        -CurrentSku $currentSku `
        -TargetSku $TargetSku
}

Write-Output "SKU validation successful."

# ==============================================================================
# 7. Idempotency check
# ==============================================================================

if ($currentSku -eq $TargetSku) {

    Return-Result `
        -Succeeded $true `
        -Result 'NoOp' `
        -Message "App Service Plan is already using SKU '$TargetSku'." `
        -CurrentSku $currentSku `
        -TargetSku $TargetSku
}

# ==============================================================================
# 8. Dry Run
# ==============================================================================

if ($DryRun) {

    Return-Result `
        -Succeeded $true `
        -Result 'DryRun' `
        -Message "DRY RUN: SKU would change from '$currentSku' to '$TargetSku'." `
        -CurrentSku $currentSku `
        -TargetSku $TargetSku
}

# ==============================================================================
# 9. Apply SKU change
# ==============================================================================

Write-Output "Applying SKU change..."
Write-Output "$currentSku -> $TargetSku"

if (-not $currentCapacity -or $currentCapacity -lt 1) {
    $currentCapacity = 1
}

$apiUri = "/subscriptions/$subscriptionId" +
          "/resourceGroups/$resourceGroup" +
          "/providers/Microsoft.Web/serverfarms/$planName" +
          "?api-version=2022-03-01"

$body = @{
    location = $location
    sku = @{
        name     = $TargetSku
        capacity = $currentCapacity
    }
}

if (-not [string]::IsNullOrWhiteSpace($planDetails.Kind)) {
    $body.kind = $planDetails.Kind
}

$jsonBody = $body | ConvertTo-Json -Depth 5

try {

    $response = Invoke-AzRestMethod `
        -Method PUT `
        -Path $apiUri `
        -Payload $jsonBody

    if ($response.StatusCode -notin @(200, 202)) {

        Return-Result `
            -Succeeded $false `
            -Result 'ScaleFailed' `
            -Message "Azure returned HTTP $($response.StatusCode): $($response.Content)" `
            -CurrentSku $currentSku `
            -TargetSku $TargetSku
    }

}
catch {

    Return-Result `
        -Succeeded $false `
        -Result 'ScaleFailed' `
        -Message "SKU update failed: $($_.Exception.Message)" `
        -CurrentSku $currentSku `
        -TargetSku $TargetSku
}

# ==============================================================================
# 10. Success
# ==============================================================================

Return-Result `
    -Succeeded $true `
    -Result 'Changed' `
    -Message "Successfully changed App Service Plan '$planName' from '$currentSku' to '$TargetSku'." `
    -CurrentSku $currentSku `
    -TargetSku $TargetSku