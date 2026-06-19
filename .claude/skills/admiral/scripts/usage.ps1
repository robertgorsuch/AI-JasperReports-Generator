# usage.ps1 — Consumption and storage usage queries.
#
# Usage:
#   .\usage.ps1 -Action current
#   .\usage.ps1 -Action storage
#   .\usage.ps1 -Action high-watermark
#   .\usage.ps1 -Action compute-summary
#   .\usage.ps1 -Action timeseries  [-From "2026-01-01"] [-To "2026-06-30"] [-Granularity daily|hourly]
#   .\usage.ps1 -Action consumer

param(
    [ValidateSet("current","storage","high-watermark","compute-summary","timeseries","consumer")]
    [string]$Action = "current",

    [string]$From,
    [string]$To,
    [ValidateSet("daily","hourly","")]
    [string]$Granularity = "daily"
)

. "$PSScriptRoot\_admiral_common.ps1"

switch ($Action) {

    "current" {
        Write-Host "=== Current Aggregated Usage ===" -ForegroundColor Cyan
        $r = Invoke-AdmiralApi -Path "/usage/current"
        Write-Host "  Tenant:           $($r.tenant)"
        Write-Host "  Total AU-hours:   $($r.totalAUhours)"
        Write-Host "  Consumed AU-hrs:  $([math]::Round($r.consumedAUhours, 2))"
        Write-Host "  Remaining AU-hrs: $([math]::Round($r.remainingAUhours, 2))"
        Write-Host "  Percent used:     $([math]::Round(($r.consumedAUhours / $r.totalAUhours) * 100, 1))%"
        Write-Host ""
        Write-AdmiralResult $r
    }

    "storage" {
        Write-Host "=== Current Storage Usage ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/usage/current/storage")
    }

    "high-watermark" {
        Write-Host "=== Storage High-Water Mark ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/usage/storage/high-watermark")
    }

    "compute-summary" {
        Write-Host "=== Compute Usage Summary ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/usage/summary/compute")
    }

    "timeseries" {
        $qs = [System.Collections.Generic.List[string]]::new()
        if ($From)        { $qs.Add("from=$([uri]::EscapeDataString($From))") }
        if ($To)          { $qs.Add("to=$([uri]::EscapeDataString($To))") }
        if ($Granularity) { $qs.Add("granularity=$Granularity") }
        $q = if ($qs.Count -gt 0) { "?" + ($qs -join "&") } else { "" }
        Write-Host "=== Usage Time Series$q ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/usage/details/timeseries$q")
    }

    "consumer" {
        Write-Host "=== Consumer Usage Details ===" -ForegroundColor Cyan
        Write-AdmiralResult (Invoke-AdmiralApi -Path "/usage/details/consumer")
    }
}
